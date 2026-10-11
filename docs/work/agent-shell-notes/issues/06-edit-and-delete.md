---
title: Edit and delete notes in the review
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [002]
---

## What to build

A wdired-style edit mode for note texts, and deletion keys. Design: §5.3,
§5.2 (`e`, `C-c C-e`, `C-x C-q`, `k`, `D`).

## Acceptance criteria

- [x] `C-c C-e` and `C-x C-q` enter edit mode; `e` enters it with point in the note at point.
- [x] Only note texts (and the request) are editable; headings, locations and quotes stay read-only.
- [x] `C-c C-c` commits every changed text to the notes and leaves edit mode; `C-c C-k` reverts and leaves.
- [x] Emptying a text keeps the note as quote-only.
- [x] Mark and navigation keys are inactive in edit mode; the mode line shows `Edit`.
- [x] `k` deletes the note at point without asking; `D` deletes marked notes after confirmation (uses marks when present, otherwise skip that case until marks land).

## Blocked by

- [Capture a note from a file and see it in the review](02-file-capture-and-review.md)

## Comments

claude, 2026-10-11. Commits: ecc0db0 (edit mode, only texts writable),
9cf7462 (commit, revert, emptied text), 2385937 (`e`; a capture during
edit mode does not wipe edits), 79cac43 (`k`), 6dd008d (cleanup), 1fb5c59 (in edit mode `C-x C-q` and
`C-c C-e` commit and leave, as in wdired; before, `C-x C-q` fell through
to the global `read-only-mode`).

Seams tested (picked from §11, not confirmed with Bill): the review keys
(`C-x C-q`, `C-c C-e`, `e`, `k`, and `C-c C-c`/`C-c C-k`/typing via
`key-binding` in edit mode), asserted against `agent-shell-notes--notes`,
the `-id`/`-field` text properties and whether an insert at a position
signals `text-read-only`. Each passing-first test was mutation-checked
(removing the boundary `rear-nonsticky`, the commit write, or the refresh
guard makes it fail).

Verified: `make check` green (27 tests, evil test skipped).

How it works: like wdired, edit mode swaps the local map to
`agent-shell-notes-edit-mode-map` (parent `markdown-mode-map`, plus
`C-c C-c`/`C-c C-k`), so every review key is inactive, including the
mark keys ticket 03 adds, with no list to maintain. This differs from
§5.3's wording ("same `keymap` property as the request body"); the
request body does not exist yet (ticket 04 owns it). The draw gives every
note a text slot in edit mode (empty for quote-only notes), tracked by
markers, and makes the char before each slot `rear-nonsticky` for
`read-only`. Also fixed: the first char of the review was insertable
(nothing before it); it is now `front-sticky` read-only.

Known gap: `M-x agent-shell-notes-edit-mode` while editing turns the
mode off and drops the edits (the keys go through commit/revert).

Assumptions: `e` puts point at the end of the note's text. `k`/`e` off a
note signal `user-error "No note at point"`. While edit mode is on, a
capture does not redraw the review; leaving edit mode draws it.

Not done: `D` (delete marked, confirming) waits for ticket 03's marks;
its box stays open. The request part of "only note texts (and the
request)" waits for ticket 04.

Unverified: the `Edit` lighter is checked in `minor-mode-alist` only
(batch `format-mode-line` returns ""). Under evil, normal state still
shadows letter keys (see ticket 02). Undo after leaving edit mode is not
handled.

claude, 2026-10-11. Commit: 189dfff (`D`, `agent-shell-notes-delete-marked`).

Seam tested (the same as `k`, not confirmed with Bill): the `D` key
through the review map, asserted against `agent-shell-notes--notes`,
`agent-shell-notes--marks` and the `-id` runs in the buffer. The test
failed first (key unbound); the declined case fails if the confirmation
is removed.

Verified: `make check` green (37 tests, evil test skipped).

Decisions: confirmation uses `yes-or-no-p`, as dired's deletion does,
with the prompt "Delete N marked notes? ". No marks:
`user-error "No marked notes"`. Declining changes nothing. Only marked
ids that are still notes are counted and deleted; the mark list is then
emptied, so stale ids go too. Edit mode already disables `D` (its own
local map).

Still open on this ticket: the request part of "only note texts (and the
request)" waits for ticket 04.

claude, 2026-10-11. Closed after ticket 04 merged: the request body stays
writable in edit mode (`agent-shell-notes-review-request-survives-redraws`
asserts it after `C-x C-q`). `make check` green (52 tests, evil test skipped).
