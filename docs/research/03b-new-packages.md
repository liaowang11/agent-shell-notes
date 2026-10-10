# Emacs annotate-and-send-to-agent packages: new candidates (survey of 2026-10-10)

Scope: packages that let you annotate (a) Magit diff buffers, (b) file buffers, (c) non-file buffers
(for example an agent-shell transcript), then gather the notes into one batch for a coding agent.
Packages already covered elsewhere are excluded, except the re-checks of reviewer.el and hunk-notes.

Method: `gh search repos` (Emacs Lisp, updated since 2025-06), `gh search code`, web search (GitHub,
Reddit, HN, Sacha Chua's Emacs News), and `gh api` for metadata, commits and source. Stars and dates
come from `gh api repos/...` on 2026-10-10.

Key: V = I checked it in the source. R = the README says so; I did not check it. ? = unknown.

## 1. Re-checks

### reviewer.el: https://github.com/SreenivasVRao/reviewer.el
- Compare view of the new work: https://github.com/SreenivasVRao/reviewer.el/compare/eb69ed60897c...develop
- No license file (GitHub reports none). 12 stars. Last push 2026-09-15.
- `main` is still at eb69ed60897c (2026-08-23). **`develop` is 13 commits ahead** (2026-09-12 to 09-15):
  - Reply threads on annotations (0717ae01).
  - A new `reviewer-treemacs.el` (721 lines): a tree and detail sidebar that lists annotations,
    refreshes itself when they change, and loads only when you turn it on.
  - **Project-wide export** (8626e550): `reviewer-render-project` and the yank variants (P/Y/E).
    V: `reviewer--project-buffers` gathers every live annotated buffer whose file, or whose
    `default-directory` for a buffer with no file ("e.g. a magit diff"), is inside the project
    root. A buffer with no file is labelled `buffer:<name>`. So an annotated agent-shell buffer
    whose cwd is the project would be included. I inferred that from the code and did not test it.
  - The rendered org format now uses a thread-id digest: a `threadId:` line plus one
    `author (time): text` line per participant (7e436104).
  - A posframe positioning fix.
- Still no built-in send to an agent: the output is an org buffer, the kill ring, or a file name.

### emacs-hunk-notes: https://github.com/ArthurHeymans/emacs-hunk-notes
- GPL-3.0. 9 stars. **No commits after ba37f3d70927** (2026-06-13). The repo looks dormant.

## 2. New candidates

| Package | Stars / last commit / license | (a) Magit | (b) file | (c) non-file buffer | Persists | Multi-buffer batch | Agent hand-off |
|---|---|---|---|---|---|---|---|
| **ai-code-interface.el** annotation module (tninja) https://github.com/tninja/ai-code-interface.el | 291 / 2026-10-08 / Apache-2.0 | V: own hunk-note store, overlays | V: through annotate.el | V: **no** (`buffer-file-name` required) | V: annotate.el db + `annotate-magit-reviews` | V: whole worktree (files + hunk notes) | V: compose buffer, then the chosen ai-code backend (agent-shell, ECA, claude-code, ...) |
| **scholia** (srnnkls) https://github.com/srnnkls/scholia | 0 / 2026-10-09 / MIT | V: records file@revision; redraw after a Magit refresh not confirmed | V | V: live-buffer source, kept only while the buffer lives | V: SQLite per session | V: named sessions; export of a whole session | V: herdr only; otherwise kill ring, buffer or file |
| **collab-comments** (clhodapp) https://github.com/clhodapp/collab-comments | 0 / 2026-08-30 / GPL-3.0 | ? (no Magit code; overlays get re-anchored by text on re-render) | V | V: yes, and persists if the mode sets `collab-comments-document-key` | V: `collab-comments.eld` | V: `collab-comments-all-threads` | the agent pulls notes via Lisp/MCP (R: you supply the bridge) |
| **revu** (jxonas) https://github.com/jxonas/revu | 1 / 2026-09-29 / GPL-3.0 | R: own magit-section review buffer; optional bridge from `magit-diff` | R: `revu-file` (own buffer) | R: only a unified diff in a buffer | R: `.revu/reviews/*.json` | R: one review = one diff/file | R: agent reads/writes the JSON file; revdiff-markdown export |
| **magit-review** (ragone) https://github.com/ragone/magit-review | 2 / 2026-08-19 / MIT | V: overlays in real magit-diff buffers, re-applied on `magit-refresh-buffer-hook` | no | no | V: JSON under `magit-review/` | per diff session | V: Markdown to kill ring |
| **ai-review-mode** (hyakt) https://github.com/hyakt/ai-review-mode | 0 / 2026-08-04 / MIT | R | R | ? | ? | R: per buffer | R: herdr backend (pluggable) |
| **magit-cr** (iwahbe) https://github.com/iwahbe/magit-cr | 0 / 2026-03-10 / GPL-3.0 | R | no | no | ? | R | R: Markdown to kill ring |
| **magit-review** (bilus) https://github.com/bilus/magit-review | 0 / 2026-07-26 / none | R: writes `REVIEW.md` | no | no | R: `REVIEW.md` | R | file only |
| **claude-emacs-annotate** (manzaltu, claude-code-ide author) https://github.com/manzaltu/claude-emacs-annotate | 0 / 2026-08-23 / none | no | R | no | R: per-project store | R | R: Claude Code plugin skills via emacsclient |
| **emacs-claude-code `ecc-review`** (wakamenod) https://github.com/wakamenod/emacs-claude-code | 5 / 2026-09-27 / GPL-3.0 | R: diff-mode/ediff of session changes | no | no | R | R: one prompt | R: own Claude CLI client + MCP review tools (PR #111 merged 2026-10-02) |
| **roost** (csheaff) https://github.com/csheaff/roost | 0 / 2026-10-10 / none | R: `;` note on Magit lines, `@` send (PR #4 merged 2026-10-09) | no | no | R: `roost-notes-file` | R: per task | R: its own tmux/worktree agents |
| **agent-review** (valpfft) https://github.com/valpfft/agent-review | 0 / 2026-07-10 / GPL-3.0 | R: annotations inside ediff | R | no | R: `.git/agent-review/session.eld` | R: per file | R: `claude` CLI applies them, then git-absorb |
| **agent-shell-org-remark** (proteusvacuum) https://github.com/proteusvacuum/agent-shell-org-remark | 0 / 2026-08-23 / MIT | R: not supported | R | no | R: org-remark | no | R: one agent-shell ACP session per highlight (not a batch) |
| **crit-magit** (askdkc) https://github.com/askdkc/crit-magit | 1 / 2026-09-08 / GPL-3.0 | R | no | no | R: buffer only | R | R: Markdown or DSH ACP review |

Tools outside Emacs that were seen and left out because none has an Emacs port: revdiff (it can open as an overlay
in Emacs vterm, which hosts it but is not a port), herdr-reviewr, tuicr, plannotator, diffity, meatcheck.

Looked at and rejected because they do not do annotate-then-send: pi-magit-review (opens Magit
from pi, no notes), inline-review (phye; forge PR comments), shipit and emacs-pr-review (forge PR
review), magit-hutch (the AI writes the review), gptel-annotate (the LLM annotates your buffer, the
reverse direction), branch-review.el (navigation only), bismuth (CR comments written into the
source), org-linenote and emacs-virtual-comment (plain notes, no agent hand-off).

## 3. Source checks (V items)

### ai-code-interface.el (https://github.com/tninja/ai-code-interface.el): `ai-code-annotation.el`, `ai-code-annotate-magit.el`, `ai-code-annotation-list.el`
- Added 2026-10-05 (commit 0e29ab6bda, PR #528), so the module is five days old.
- Entry point: `ai-code-address-code-annotation`, a menu with add/edit, browse, "ask AI at point",
  "ask AI about all", delete and clear. It needs annotate.el 2.5.0+.
- File buffers use annotate.el itself. `ai-code--annotation-at-point` and `-edit` raise
  `user-error "Buffer is not visiting a file"` / "Visit a source file". **Non-file buffers are not
  supported.**
- Magit uses its own store, `ai-code-annotate-magit-file` (default `annotate-magit-reviews` in the
  Emacs directory). Each note keeps the repository, file and hunk text, and is matched back to the
  hunk by file and hunk text when the buffer refreshes. It draws with annotate.el's overlays and faces.
- Batching: `ai-code--annotation-sources` reads every annotate.el database plus every live
  `annotate-mode` buffer in the git worktree. `ai-code--annotation-report` adds the Magit hunk notes.
  Each note is rendered with its ID, reply-to, a MATCHED/UNMATCHED status, line numbers, and fenced
  note and source text.
- Sending: `ai-code--annotation-send` wraps the report in a fixed "suggestions ONLY, do not modify
  files" prompt, opens it in `ai-code-compose-read` for you to edit, then calls
  `ai-code--write-prompt-to-file-and-send`, which goes to the selected backend. `ai-code-backends.el`
  lists `agent-shell` and `eca` among others. The suggestions-only wording is hardcoded.

### scholia: https://github.com/srnnkls/scholia
- A rewrite of annotate.el ideas; the README says no annotate.el code is kept. It needs the
  author's `cera` package, which no archive carries, and Emacs built with SQLite.
- `scholia-locate.el` has three source kinds: `file`, `git` (file at a revision) and `buffer`. Any
  buffer that no location function claims falls back to `scholia-locate--generic-position`. That
  function gives the buffer a random md5 id, kept in a buffer-local variable. So **non-file buffers
  work, but the link lasts only while that buffer object lives.** After it dies, exports fall back to
  the stored snapshot (`bounded-full`, 256 KiB by default).
- `scholia-magit.el` (65 lines) only maps a diff line to the file, the line, and the old or new
  revision. Outside `scholia-forge` there is no `magit-refresh-buffer-hook`, so I could not confirm
  that notes are redrawn in the Magit buffer after `g`. Their saved location points at the file
  at that revision.
- Batching uses named sessions, each a SQLite database. `scholia-export-session` renders a whole
  session in rustc style, as a diff, or as commented source, to the kill ring, a buffer or a file.
- Sending is built in only for herdr (`scholia-herdr.el`: `herdr-api-agent-prompt` or
  `pane-send-text`), and it records which annotations were sent. herdr support is left out of the
  package and of CI. There is no agent-shell, gptel or claude-code integration.
- Activity: 58 commits since 2026-08-25, last 2026-10-09. 0 stars.

### collab-comments: https://github.com/clhodapp/collab-comments
- One file, 1038 lines, no dependencies, Emacs 26+, CI against 26.1 through 31.1.
- Threads are overlays holding `(:author :time :text)` comments. A global registry backs
  `collab-comments-all-threads`, which lists every buffer's threads, so a batch across buffers is
  one call.
- `collab-comments-document-key` is buffer-local. Its docstring names "a transcript viewer might
  use session:<session-id>". With a key, threads persist and can be rebuilt after the mode
  re-renders the buffer. Without a key, threads in a non-file buffer last only for the session.
  Change hooks re-anchor threads by text when a region is replaced.
- There is no agent transport. The package exposes the functions, and the agent calls them through
  an MCP server or `emacsclient`. It has no "send batch" command, though
  `collab-comments-render-thread` gives text that is easy to join into one prompt.
- Activity: 4 commits, all on 2026-08-30. Pre-1.0.

### magit-review (https://github.com/ragone/magit-review): light check
- It re-applies overlays on `magit-refresh-buffer-hook` (`magit-review-render.el:346`), stores
  sessions as JSON under `magit-review/`, and exports Markdown with `kill-new`. Magit only.

## 4. Assessment

- No package found covers (a), (b) and (c) **and** sends one batch to agent-shell out of the box.
- The closest for the agent-shell case is **ai-code-interface.el**'s new annotation module. It
  covers (a) and (b), batches the whole worktree, and sends through the agent-shell backend. It
  cannot annotate non-file buffers, it is five days old, and its prompt is fixed to
  "suggestions only".
- **reviewer.el develop** is the only one that exports Magit, file and non-file buffers in one
  project-scoped batch with no extra dependencies. It still stops at org/kill-ring output, and
  those changes are not on `main` yet. scholia and collab-comments also cover (c) and batch across
  buffers, but scholia needs `cera` (and herdr to send), and collab-comments needs a bridge on the
  agent's side.
- **scholia** has the most thorough model: (a), (b) and (c), sessions and snapshots. It only sends to
  herdr, depends on the unpublished `cera`, has 0 stars and a single author.
- **collab-comments** has the best non-file-buffer persistence design (a document key, with
  transcripts named in the docs). It is a library for an agent to pull from, not a push-a-batch tool.

## 5. Unverified

- I loaded or ran nothing in Emacs. Behaviour claims rest on reading the code.
- R rows (revu, ai-review-mode, magit-cr, bilus/magit-review, claude-emacs-annotate, ecc-review,
  roost, valpfft/agent-review, agent-shell-org-remark, crit-magit) rest on their READMEs.
- Whether scholia redraws notes in a refreshed Magit buffer.
- Whether reviewer.el's `default-directory` scoping picks up agent-shell buffers in practice.
- The multi-word `gh search code` queries all came back empty, including ones that should have
  matched (for example nineluj/agent-review). Treat that as a tooling failure, not as evidence that
  nothing exists; code search was not really swept. I did not search emacs-devel or Mastodon
  directly. A sachachua.com-only search found reviewer.el (Emacs News 2026-08-17), inline-review and
  simply-annotate, and nothing new.
- Web search found no Reddit, HN or Emacs News write-ups for most of these. Discovery came mostly
  from GitHub search, which matches only repo names and descriptions, so packages with unusual
  names may be missing.
