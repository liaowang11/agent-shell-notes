---
title: Mark notes in the review
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [002]
---

## What to build

Dired-style marks on review notes so a later send can act on a subset.
Design: §5.1 (marks), §5.2 (`m u t U`).

## Acceptance criteria

- [ ] `m`/`u` mark or unmark the note at point, or every note the region touches, then move to the next note.
- [ ] `t` toggles all marks (from none, marks all); `U` unmarks all.
- [ ] `agent-shell-notes-mark-indicator` picks `fringe` (margin `*` on a tty) or `background`; marks are overlays, never text, and survive a redraw.
- [ ] Mark commands with point in the request section or on no note signal `user-error`.

## Blocked by

- [Capture a note from a file and see it in the review](02-file-capture-and-review.md)
