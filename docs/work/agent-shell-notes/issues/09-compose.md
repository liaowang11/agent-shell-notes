---
title: Fill the target's compose buffer instead of sending
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [004]
---

## What to build

`C-u C-c C-c` renders as a send would, then appends the text to the
target session's viewport compose buffer and switches there, so Bill can
edit before agent-shell sends. Design: §6.3, §6.2 (`:compose` slot).

## Acceptance criteria

- [x] The client plist gains an optional `:compose`; the agent-shell client appends through the viewport show-buffer path with `:append`, `:edit t`, and the disposition read back from an existing viewport (no viewport created by the read).
- [x] The text lands after an existing draft; the draft's queue/steer choice is preserved.
- [x] After-send, mark clearing, request clearing and restore-last apply as for a send.
- [x] A client without `:compose` gives a `user-error` naming the client and changes nothing.
- [x] Tests run the real viewport show-buffer code with only its header and position helpers stubbed.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)

## Comments

claude, 2026-10-11. Commit: d820ac3 (compose client slot, `C-u C-c C-c`,
tests).

Seams tested (picked from §11, not confirmed with Bill): the review's
`C-u C-c C-c` (from a note and from the request body) with the process
boundary stubbed as in 04, and the real
`agent-shell-viewport--show-buffer` with only `--update-header` and
`--position` stubbed. Asserted: the compose buffer's trimmed text, its
disposition, the selected window, that nothing was sent, the review
state and that no viewport was made on refusal.

Decisions made here:
- Compose shares `agent-shell-notes-send`; the prefix only picks the
  client's `:compose` instead of `:send`. Everything after that call
  (now: `last-target` and the message, `Composed N notes to X`) is
  common, so 05's after-send, clearing and restore-last code apply to
  compose once they go in that tail.
- The client call is wrapped in `save-current-buffer`: show-buffer
  selects the viewport window, which also makes it current, and the
  tail must act on the review. Focus still ends on the viewport.
- The `%s` in `Client %s cannot fill a compose buffer` is the client
  plist printed with `%S`: a client has no name slot and I did not add
  one. The check runs before the picker.
- Compose has no session-id guard (a starting agent is a fine time to
  draft); it keeps the dead-buffer `user-error`.
- `agent-shell-notes-agent-shell-disposition` does not apply to compose;
  the disposition comes only from an existing viewport, else nil.

Verified: `make check` green (55 tests, evil test skipped). Mutations:
passing nil instead of the read-back disposition, dropping the
no-`:compose` guard, and always calling `:compose` each fail a test.
No test starts an agent.

Unverified / open:
- Box 3 (after-send, mark and request clearing, restore-last for
  compose) is not ticked: it depends on ticket 05 landing in the shared
  send tail, and needs a compose case in 05's tests.
- `save-current-buffer` has no test; nothing in the tail reads the
  current buffer until 05.
- `:edit t` for a busy shell is not exercised (with non-empty text
  show-buffer goes to edit mode either way).
- Real compose-and-send through a live viewport (ticket 14 live-check).

claude (ticket 05), 2026-10-12. Box 3 ticked: after-send runs in the
shared tail of `agent-shell-notes-send` after `:compose` returns
(merge 670f822). `agent-shell-notes-compose-applies-after-send-and-restore`
(1ccb613) composes a marked note with a request under `archive`, checks
the tag, cleared marks and request, then restores from the compose
buffer. Dropping the after-send call fails it. `save-current-buffer`
remains untested (after-send finds the review by name).
