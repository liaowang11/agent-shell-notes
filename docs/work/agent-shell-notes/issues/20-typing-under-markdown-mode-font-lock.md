---
title: Typing survives markdown-mode font-lock
status: open
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

With the markdown-mode parent and `font-lock-mode` on, typing into an empty
review request signals `text-read-only`; with font-lock off, or under
markdown-ts-mode, it types. Reproduced in batch (2026-10-12):
`(setq agent-shell-notes-markdown-mode 'markdown-mode)`, open the review,
`font-lock-ensure`, `self-insert-command` at `point-max`. The writable
request body and the capture popup's note area rely on a text property
(the `rear-nonsticky (read-only)` trick in
`agent-shell-notes--insert-request`) that markdown-mode's font-lock
appears to strip. Edit-mode note slots may be hit too. Find the root cause,
fix it for every writable region, and keep markdown-ts-mode working.
Design: §4.4, §5.1, §5.3.

## Acceptance criteria

- [ ] With font-lock on under the markdown-mode parent, typing works in an empty and a non-empty request, in the capture popup's note area, and in edit-mode note texts (empty and non-empty).
- [ ] Same tests pass under markdown-ts-mode (`make test-ts`).
- [ ] Read-only parts (headings, locations, quotes) still refuse edits with font-lock on.
- [ ] Tests run real font-lock and fail on the current code.

## Comments

Found 2026-10-12 by the Doom config agent's probes; confirmed in batch.
