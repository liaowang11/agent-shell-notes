---
title: What one captured note looks like
type: grilling
status: closed
assignee: claude (agent-shell-annotations-b9)
blocked-by: []
---

## Question

Decide the Markdown for one entry per source, and the text around the batch,
so that the review can be sent as is:

- Magit diff: location (file, side, lines, staged/unstaged or revision), how
  much diff is quoted (selected lines, hunk, hunk header).
- File: `path:start-end` and a fenced quote.
- Transcript: which turn, quoting the agent's text, framing it as data.
- Note ids or numbering, grouping (by file? in capture order?), and the
  preamble that tells the agent how to answer.
- Where one note starts and ends in the review buffer, since marks, `n`/`p`
  and single-note editing hang on those boundaries, and what text a send of
  some marked notes assembles
  ([When a review picks its target session](003-target-session.md)).

`docs/research/04-agent-apps.md` has the formats other apps use.

## Resolution

Grilled with Bill, 2026-10-11. Formats compared: Codex app, omp and Claude
desktop (`docs/research/agent-apps/claude-desktop-diff-comments.md`, new;
Codex and omp in `codex-opencode.md` and `omp-claude.md`). Codex's diff
comment attaches every hunk the range touches, whole (`ln()` in the
VSIX `code-diff-*.js`).

This supersedes "what Bill sees for each note is what is sent for it" (map
Notes and [When a review picks its target session](003-target-session.md)):
the review is a display; text is produced only at send or copy.

- **A note is data**: source, location, quote (selected lines plus hunks
  and side for diffs; the agent's original Markdown, via
  `agent-shell-markdown-reconstruct`, for transcripts) and Bill's text.
- **Styles**: a defcustom picks `claude` (default), `codex` or `omp`; a
  command sets it for the Emacs session. No agent-to-style mapping. Each
  style copies its app's wire text verbatim, wrapper included; numbers
  (Codex `## User Comment N`, omp `## N.`) are counted per send. Data the
  package lacks (omp `Occurrence:`) is dropped. No preamble of our own.

  | | `claude` | `codex` | `omp` |
  | --- | --- | --- | --- |
  | Diff | ``In `path` at line N:`` / ``at lines S-E[ (before changes)]:`` + plain lines of one side in a language-tagged fence; a mixed selection keeps the new side | `## User Comment N` / `File:` / `Side:` / `Lines:` / `Diff hunk:` (every hunk touched, whole) / `Comment:` under `# Diff comments:` | `## Code Review Annotations` + its preamble line; `### path — new S-E` / `Path:` / `Hunk:` / `diff` fence of the selected lines (ranges are ours) |
  | File | same sentence + plain lines | ours: User Comment with `File:` / `Lines:` + fenced quote / `Comment:` | `# Feedback on path` / `## N. Feedback on:` quote / note; no `## Source` |
  | Reply in the target session | `<!-- reply N -->` (N = count, first block only; later `<!-- reply -->`) / `>` quote / blank / note, placed before the diff and file notes | `# Response annotations:` JSON with `:codex-annotation` citations | `# Feedback on your last reply` / `on Assistant message N` |
  | Quote from another session | plain `>` quote + note | same | same |
  | Request | after the notes, two blank lines | `## My request:` | after the notes |
  | Mixed batch | review order | Codex section order | review order |

- **Rendered at send**: paths relative to the note's project; when that
  differs from the target's project, the workspace is added (Codex
  `Workspace:` line, inline in the others). Staged / unstaged / commit is
  never sent.
- **Capture extent (Magit)**: region inside a hunk = its lines; no region =
  the line at point; point on `@@` = the whole hunk.
- **Review display**: Markdown, grouped by source (file + project, or
  session + turn + fragment kind), sorted by line or turn position; a new
  note lands in place. Each note: bold range, tags (staged / unstaged /
  commit, before changes), the quote folded after 6 lines, Bill's text.
  The turn index is shown, never sent. An editable **request** section
  closes the buffer; empty means notes only.
- **Marks**: a defcustom picks a fringe indicator (margin on a tty) or a
  background overlay on the whole note, not both.
- **Keys** (customizable):
  - `RET` / click on a location line or group heading: jump to the source,
    best effort.
  - `C-c C-e` (also `C-x C-q`): wdired-style edit mode. Only note text is
    editable; headings, locations and quotes stay read-only and fence the
    notes. `C-c C-c` commits, `C-c C-k` reverts. `e` enters edit mode at
    the note. Emptying a note's text does not delete it.
  - `C-c C-c` sends at once; `C-u C-c C-c` inserts the rendered text into
    the target's compose (`[viewport]`) buffer, appended after any draft,
    and switches there; `w` copies. These replace `S` and `RET`-edit of
    ticket 003, and reverse its "no wdired-style edit".
- **Client seam**: `read-session (hint)`, `send (session text)`, optional
  `compose (session text)`. A client without `compose` offers send and copy.
- Glossary: Style and Request added; Send widened.
- The `claude` template is unconfirmed by a real session:
  [Confirm the Claude desktop diff-comment template from a real session](008-confirm-claude-template.md).

## Comments

- 2026-10-11: [How the capture popup behaves](005-capture-popup.md) adds
  dired and generic-buffer sources and the `claude` sentences for thinking,
  tool calls, plans, multi-block and multi-turn regions, and
  `your last reply`.
- 2026-10-11: [Confirm the Claude desktop diff-comment template from a real
  session](008-confirm-claude-template.md) confirmed the diff template
  (`line N` for one line, language-tagged fence) and found Claude's native
  reply-comment format; the `claude` row now uses it for notes on the
  target session's own transcript.
