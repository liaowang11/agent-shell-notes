---
title: Mark notes in the review
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [002]
---

## What to build

Dired-style marks on review notes so a later send can act on a subset.
Design: §5.1 (marks), §5.2 (`m u t U`).

## Acceptance criteria

- [x] `m`/`u` mark or unmark the note at point, or every note the region touches, then move to the next note.
- [x] `t` toggles all marks (from none, marks all); `U` unmarks all.
- [x] `agent-shell-notes-mark-indicator` picks `fringe` (margin `*` on a tty) or `background`; marks are overlays, never text, and survive a redraw.
- [x] Mark commands with point in the request section or on no note signal `user-error`.

## Blocked by

- [Capture a note from a file and see it in the review](02-file-capture-and-review.md)

## Comments

claude, 2026-10-11. Commits: cf75bd7 (`m`), e6fa40e (`u`, region),
8c561f6 (`t`, `U`), 92c2149 (tests: redraw, errors, indicators).

Seams tested (picked from §11, not confirmed with Bill): the review keys
`m u t U g` through `agent-shell-notes-review-mode-map`, asserted against
the overlays carrying the `agent-shell-notes-mark` property (value = note
id) and the `agent-shell-notes-id` text property.

Verified: `make check` green (28 tests, evil test skips). Marks survive `g`
and a capture that redraws the shown review. The three tests that passed
on first run (redraw, off-note error, background) were made to fail by
removing the re-apply in the draw, the `background` branch and the error.
Buffer text is unchanged by marking.

Decisions: marks are a global list of ids, `agent-shell-notes--marks`
(§7.2/§7.3 send and restore will read and reset it). `t` inverts each
non-archived note's mark and leaves archived ones as they are (§5.2);
`:archived` is never set yet, so the test sets it by hand. `m`/`u` on the
last note mark and stay put (no "No next note" error). A region ending at
the first character of a note does not touch it. The draw re-applies
marks inside `--insert-note`; mark commands redraw only the overlays.

Unverified: the fringe bitmap (`filled-rectangle`) and the margin `*` in a
real GUI frame or tty (batch has no graphic display and takes the margin
branch; only the overlay's display spec and `left-margin-width` are
checked). The `agent-shell-notes-mark` face inherits `region`; in themes
where `region` has no foreground, the fringe bitmap takes the fringe's
default colour.

Open: the review has no `# Request` section yet, so "point in the request
section" is covered only by the no-note case. Stale ids left by a delete
(ticket 06) are harmless to `t`, which rebuilds the list from the notes,
but a send must intersect the marks with the note list. Edit mode must
disable `m u t U` (§5.3).
