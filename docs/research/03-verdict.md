# Verdict: build a personal annotation package

Date: 2026-10-10. Third round after the [package survey](01-package-survey.md)
and the [annotation-model survey](02-annotation-models.md). Supporting
reports: `03a-fit-check.md` (hunk-notes and reviewer.el against
agent-shell and Magit, with batch smoke tests) and
`03b-new-packages.md` (2025–2026 package sweep).

## Verdict

**Build a small personal package** (working name `agent-shell-annotate`) and
borrow ideas, not code dependencies. No existing package covers all three
sources, and fixing the closest candidates is more work than writing the missing
layers. Each candidate fails at least one hard requirement:

| Candidate | Magit diff | File | agent-shell transcript | Send to agent-shell | Disqualifier |
| --- | --- | --- | --- | --- | --- |
| emacs-hunk-notes | diff/revision buffers only | no | no | yes, no target shell | Dormant since 2026-06-13. Breaks in magit-status. Credits lines under new/deleted/renamed headings to the wrong file. Notes vanish on `g`. |
| reviewer.el | display lines only | yes | partly | no | **No license** (can't legally fork). Overlays are destroyed by Magit refresh, tool-call body updates, table re-render and the viewport's `erase-buffer`, all reproduced in batch. |
| ai-code-interface annotation (tninja, Apache-2.0, 2026-10-05) | yes, redraws on refresh | yes (via annotate.el) | **refuses** ("Buffer is not visiting a file", `ai-code-annotation.el:408`) | only through `(require 'ai-code-backends)` (`:519`) | The sender needs the whole ai-code framework (transient + magit) loaded next to agent-shell. Hard-coded "suggestions ONLY, do NOT modify files" prompt (`:379`). Two stores (annotate.el plus its own). |
| scholia | yes | yes | yes, until the buffer dies | herdr only | 0 stars; needs the author's unpublished `cera`. Not shown to redraw after Magit refresh. |
| collab-comments (GPL-3) | no | yes | yes, keyed and restorable after re-render | no (agent pulls via MCP) | No Magit, no push to agent-shell. |
| org-remark / annotate.el / simply-annotate | no or weak | yes | need a custom identity | no | Covered in round 1; each needs the same glue. |

The strongest reuse plan would be to adopt ai-code-interface for diffs and
files and build only the transcript part. It is rejected because the transcript
part needs its own collector and sender anyway. Those would then serve all
three sources, so adoption would save only the ~400-line Magit section mapping.
That mapping is Apache-2.0 and can be copied with attribution.

The checks were source reading plus batch tests of reviewer.el and hunk-notes.
Nothing was run in Bill's Doom server.

## Why building is cheap

Every hard part already exists, either in Bill's own code or in an API:

- **Magit anchor:** `magit-diff-hunk-line` (`magit-diff.el:2041`) and
  `magit-file-at-point` convert a diff point to file + old/new line from the
  section tree, with no unified-diff text parsing. That parsing is what makes
  hunk-notes fragile. ai-code-interface shows the redraw pattern:
  `magit-refresh-buffer-hook` (`ai-code-annotate-magit.el:471`).
- **Transcript anchor:** every agent-shell block has an
  `agent-shell-ui-state` text property with `:qualified-id`, which is
  `<request-count>-<block-id>` (`agent-shell-ui.el:190`, `agent-shell.el:3838`).
  Store `(session-id, qualified-id, quote)` and find the note again by
  searching for the quote inside that block after a re-render. That is the
  collab-comments "document key + restore" idea applied to agent-shell's own
  identity.
- **File anchor:** file path + line range + quote, re-found with a quote
  search near the old position (annotate.el / org-remark approach).
- **Delivery:** `agent-shell-insert :shell-buffer` (`agent-shell.el:12983`),
  `agent-shell--read-shell-buffer` for picking the target, and the busy-safe
  insert-or-queue pattern from `agent-shell-send-region`. agent-shell-side
  already has the compose-buffer flow (quote lands, nothing is sent).

Size estimate: 1–2k lines with ERT tests, about the size of `openusage.el`
(1.1k) and `agent-shell-side` (2.2k). It is not open-ended.

## Scoped MVP

1. **Data:** a note is a plist: `id`, `source` (`:file` / `:magit` / `:transcript`),
   anchor (file + side + range + revision, or session + qualified-id), `quote`, `body`,
   `created`, `sent-at`.
2. **Capture:** one command, `annotate-dwim`, dispatches on major mode
   (magit-diff/status/revision, agent-shell, file buffer). Notes are drawn as
   overlays that are redrawn from the data, never stored in them.
3. **Redraw:** `magit-refresh-buffer-hook`, plus a hook or advice after
   agent-shell fragment updates and viewport rebuilds.
4. **Collect:** a project-wide (or global) list buffer, and a Markdown
   renderer that groups notes by source and includes the quote, the location
   and the commented hunk.
5. **Send:** pick the shell, insert into its compose buffer or prompt without
   submitting, then mark the batch sent. Keep "sent" separate from "resolved".
6. **Defer:** reply threads, agent-written replies, MCP pull, drift UI.

Borrow, with attribution where code is copied: ai-code-interface (Apache-2.0)
for the Magit section-to-note mapping and refresh hook; collab-comments
(GPL-3.0) for keyed restore; hunk-notes (GPL-3.0) for its prompt layout.
reviewer.el is ideas only, because it has no license.

## Decisions for Bill

- **Persistence scope:** keep only Magit/diff reviews across restarts, or
  file and transcript notes too? Transcript notes outlive the buffer only if
  they anchor to the saved transcript file. Persistence roughly doubles the
  anchor and restore work.
- **Location of these research files:** they are untracked at the flake
  root, together with `.scratch/`, which is not gitignored. They probably
  belong in the new package's repo or in PARA, not in the flake.

## Still unverified

- Live behavior in Doom: evil keys, conflicts with Magit highlight overlays,
  Bill's difftastic toggle (`C-c C-d` gives a `@@ line N @@` heading, so
  `magit-diff-hunk-line` needs a check there).
- agent-shell has no general post-update hook. The only hooks are
  `agent-shell-ui-post-expand-fragment-at-point-hook` and
  `agent-shell-section-functions` (`agent-shell.el:7641`, not yet checked for
  whether it fires on body updates). Redrawing after a tool-call body update
  (`agent-shell-ui.el:568`) or a viewport rebuild may need advice on an
  internal function, or a small hook added in Bill's fork.
- Whether `request-count` stays stable when a resumed session replays its
  history. If not, the transcript anchor falls back to session + quote.
- ai-code-interface's annotation module is five days old, so it may still grow
  non-file support. It is worth re-checking before starting, but its framework
  dependency stays.
