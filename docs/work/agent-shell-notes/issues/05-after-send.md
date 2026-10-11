---
title: After-send modes and restore-last
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [004]
---

## What to build

What a successful send does to the notes that went out, and one level of
undo for it. Design: §7, §5.2 (`x`, `C-c C-r`).

## Acceptance criteria

- [x] `agent-shell-notes-after-send` picks `remove` (default), `archive` or `keep`; `agent-shell-notes-set-after-send` changes it for the session.
- [x] `archive`: notes stay in place, dimmed, tagged `sent to <session>`; resending updates the tag; `t` skips archived notes; `x` purges them without asking.
- [x] Marks clear after every send in every mode; the request goes with every send and clears after it; `w` applies none of this.
- [x] `agent-shell-notes-restore-last` (`C-c C-r` and global) restores positions under `remove`, old tags under `archive`, and marks and request in every mode; a second call with nothing stored signals `user-error`.
- [x] A failing send leaves everything unchanged.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)

## Comments

claude, 2026-10-12. Commits: 0bc92f0 (`remove`, marks and request clear),
0e559a0 (`archive`, `keep`, `set-after-send`), 6e4b8d1 (`x`), b167d24
(restore-last), 670f822 (merge of 09 compose), 1ccb613 (compose test).

Seams tested (picked from §11, not confirmed with Bill): the review keys
(`C-c C-c`, `C-u C-c C-c`, `x`, `t`, `C-c C-r`, `w`) and the global
`agent-shell-notes-restore-last` / `-set-after-send`, with only the process
boundary stubbed as in 04 (compose runs the real viewport code as in 09).
Asserted against `agent-shell-notes--notes` (ids, `:archived`),
`agent-shell-notes--marks`, the request body, the `-id` runs, the
location field text and the note's overlay faces.

Decisions:
- One tail helper, `agent-shell-notes--after-send (notes session)`, called
  from `agent-shell-notes-send` right after `:send`/`:compose` returns. It
  stores the restore data, applies the mode, clears marks and request, and
  redraws. Ticket 14 (send-all) should call it too.
- Restore store `agent-shell-notes--last-send`: mode used, marks, raw
  request, and per note (NOTE INDEX PRIOR-ARCHIVED). Under `remove` notes
  are reinserted at their old list indexes in ascending order, so notes
  captured since stay where they are (tested); notes already in the list
  are skipped. The mode stored at send time decides the restore, not the
  current option. The store empties after a restore.
- `:archived` is set in place on the note object (`setcdr`, or `nconc` if
  the key is missing), since the review's selected notes are the list's
  own objects.
- Archived tag: `` `sent to NAME` `` appended inside the `location` field
  after the bold range, NAME from the client's `:name`. Dimming is an
  overlay with face `agent-shell-notes-archived` (inherits `shadow`) over
  the whole note, so font-lock cannot wipe it. I did not add the
  `agent-shell-notes-tag` face (§10) to avoid colliding with ticket 07's
  tags; the tag text uses the location face for now.
- The request is cleared/restored by rewriting the body in the review
  buffer (`agent-shell-notes--set-request`); there is still no request
  variable.
- `x` with nothing archived is a no-op with a message; it drops purged
  ids from marks and unfolded quotes. `C-c C-r` also works from the
  request body (markdown-mode leaves it unbound, so it falls through to
  the review map; checked in batch).
- `set-after-send` uses `completing-read` over the three names and
  `setq` (session only, nothing saved).
- `send-picker-order` now binds `after-send` to `keep`: it sends the same
  note twice.

Verified: `make check` green (64 tests, evil test skipped). Mutations:
restoring by appending instead of by index, not storing marks, and
dropping the after-send call from the shared tail each fail tests. A
failed send leaves notes, marks and request equal and stores nothing
(restore afterwards still undoes the earlier successful send). `w`
stores nothing. No test starts an agent.

Unverified / limits:
- The dim overlay and tag in a real GUI frame with markdown font-lock
  (batch never fontifies).
- If the review buffer is dead at restore time, the request has nowhere
  to go and is dropped; notes and marks still restore.
- If the review is in edit mode at a send-all or restore, the refresh is
  skipped (as for captures); the request body is still rewritten.
- `remove` restore after other notes were deleted in between may land a
  note one place off (indexes, not neighbours).
- 09's `save-current-buffer` around the client call is still untested:
  after-send finds the review by name, so dropping it changes no test.
