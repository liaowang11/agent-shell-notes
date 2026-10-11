---
title: The codex style
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [007, 008, 010]
---

## What to build

`agent-shell-notes-style` set to `codex` renders every source kind in the
Codex app's wire format. Design: §8 shared rules, §8.2.

## Acceptance criteria

- [ ] `agent-shell-notes-set-style` switches styles for the session; `claude` stays the default.
- [ ] Own-session transcript notes render as the `# Response annotations:` block with its verbatim instruction and a JSON array of `text` and optional `annotation`.
- [ ] Other-session quotes render as a plain quote and text between the annotations and the diff comments.
- [ ] `# Diff comments:` holds diff, file, dired and fallback notes as `## User Comment N` numbered across the send, with `File:`, `Workspace:` when the project differs, `Side:` (`R`, `L`; mixed is `R`), `Lines:`, every stored hunk whole in a `diff` fence, `Comment:`; file notes use a language fence; dired uses `Files:`, fallback `Buffer:` and `Lines:`.
- [ ] `## My request:` closes the text when the request is non-empty.
- [ ] Golden files: diff, old side, mixed, file, own-session reply, other-session quote, dired, fallback, request-only, mixed batch, cross-project, numbering over two sends.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)
