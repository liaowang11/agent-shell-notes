---
title: The codex style
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [007, 008, 010]
---

## What to build

`agent-shell-notes-style` set to `codex` renders every source kind in the
Codex app's wire format. Design: §8 shared rules, §8.2.

## Acceptance criteria

- [x] `agent-shell-notes-set-style` switches styles for the session; `claude` stays the default.
- [x] Own-session transcript notes render as the `# Response annotations:` block with its verbatim instruction and a JSON array of `text` and optional `annotation`.
- [x] Other-session quotes render as a plain quote and text between the annotations and the diff comments.
- [x] `# Diff comments:` holds diff, file, dired and fallback notes as `## User Comment N` numbered across the send, with `File:`, `Workspace:` when the project differs, `Side:` (`R`, `L`; mixed is `R`), `Lines:`, every stored hunk whole in a `diff` fence, `Comment:`; file notes use a language fence; dired uses `Files:`, fallback `Buffer:` and `Lines:`.
- [x] `## My request:` closes the text when the request is non-empty.
- [x] Golden files: diff, old side, mixed, file, own-session reply, other-session quote, dired, fallback, request-only, mixed batch, cross-project, numbering over two sends.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)

## Comments

claude, 2026-10-12. Commits: 9fea228 (`agent-shell-notes-set-style`,
style dispatch in `--render`, codex diff comments), 8bf6575 (file, dired,
fallback comments, `Workspace:`), 897e97b (response annotations,
other-session quotes, request).

Seam tested (picked from §11, not confirmed with Bill): `--render` with
`agent-shell-notes-style` bound to `codex`, against
`tests/golden/codex-*.txt` built from literal note alists; the
set-style command through a stubbed `completing-read`.

Decisions, from the shipped bundle (`app-initial-fee819fe4f22.js`,
`EE`, `n9t`, `wE`, re-read for this ticket):
- Every section and every `## User Comment N` is preceded by one blank
  line; `# Diff comments:` has a blank line before comment 1. The app's
  leading and trailing newlines are dropped, as in `claude`.
- Request-only sends the bare request: `wE` adds `## My request:` only
  after a section. Deviation: the app also writes the header with an
  empty request; we follow the ticket and omit it.
- `Comment:` is always written; an empty note text leaves it empty, as
  the app does.
- The hunk fence follows the shared fence rule (the app always uses three
  backticks; same output unless a hunk holds backticks). Hunks go out
  verbatim with their final newline dropped, joined by newlines; the
  per-line trim applies to quotes, not hunks.
- JSON via `json-serialize`, matching `JSON.stringify`: `/` and non-ASCII
  raw, short escapes. Emacs 30+ returns UTF-8 bytes, decoded.
  Own-session notes with empty text stay in the array without
  `annotation`; no count cap.
- `File:` stays relative to the note's project; `Workspace:` is the
  note's project without the trailing slash, only when a target exists
  and its project differs. Dired notes get it too; fallback notes never
  (no path).
- Fallback: `Buffer:`, `Lines:`, then the quote in a `text` fence (the
  buffer has no file the agent could read), then `Comment:`.
- Dispatch: a `'codex` arm in the one `pcase` on the style in
  `--render` (merged with ticket 13's; `_` falls back to `claude`).
  Ticket 13's `--trim-lines` replaced my identical copy at the merge. `set-style` reads
  its choices from the defcustom type, so a new style only adds a
  `const`. Other-session quotes reuse `--claude-quote-block`.

Verified: `make check` green on this branch (116 tests), and again after
merging main fc78e4b (132 tests, evil test skipped); set-style offers
claude, codex and omp. Unverified: the `source` field shape (dropped, per DESIGN);
`json-serialize` output on Emacs 29.1 (jansson) is assumed equal, CI
will show; no live send to a Codex agent.
