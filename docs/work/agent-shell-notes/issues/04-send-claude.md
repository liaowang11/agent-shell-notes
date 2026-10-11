---
title: Send a review to an agent-shell session in the claude style
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [003]
---

## What to build

From the review, `C-c C-c` renders the marked notes (or the note at point)
and the request in the `claude` style, asks for a live agent-shell session,
and sends the text as one prompt. `w` copies the same text instead.
Design: §5.1 (request body mechanism), §6.1, §6.2, §6.4, §8 shared rules,
§8.1 (file notes and request only).

## Acceptance criteria

- [x] The request body is always editable; everything else stays read-only; typing `m` in the request inserts an `m`.
- [x] `claude` rendering of file notes matches golden files: `In \`path\` at line N:` / `at lines S-E:`, fence one backtick longer than the longest run inside (min 3), language from the extension table then major mode then `text`, trailing whitespace trimmed, snippet-line and path sanitizing, request after two blank lines, request-only send.
- [x] A note whose project differs from the target's uses an absolute path.
- [x] The client is a plist (`:read-session`, `:send`, `:name`, `:session-id`, `:turn-count`); the agent-shell client picks over all live shells sorted last target, then matching projects, then the rest, and sends through the prompt-send seam with `agent-shell-notes-agent-shell-disposition`.
- [x] No live shell: `user-error`, review untouched. No marks and no note at point: `user-error`.
- [x] A send counts when the send seam returns normally; an error leaves notes, marks and request unchanged.
- [x] `w` copies the rendered text and changes nothing.
- [x] Tests stub only the process boundary (prompt-send, the shell picker, the shell list).

## Blocked by

- [Mark notes in the review](03-marks.md)

## Comments

claude, 2026-10-11. Commits: 3de1fbc (editable `# Request` section),
b8eae91 (claude rendering of file notes, golden files), 9af5f42
(agent-shell client, `C-c C-c`, `w`).

Seams tested (picked from §11, not confirmed with Bill): the review keys
(`C-c C-c`, `w`, typing in the request body) with only
`agent-shell-buffers`, `agent-shell--read-shell-buffer` and
`agent-shell--prompt-send` stubbed, asserted against what the stubs
received, the kill ring, and the note list, marks and request before and
after; `agent-shell-notes--render` against `tests/golden/claude-*.txt`
built from literal note alists with fake `/proj/` paths.

Bill's decisions (2026-10-11):
- Picker: DESIGN §6.1 as written; the sorted list goes to
  `agent-shell--read-shell-buffer :buffers`. agent-shell-vertico re-sorts
  by recency in Bill's setup; known limitation, not this package's bug.
- Send guard: a target with no session id (agent not started, where
  `agent-shell--prompt-send` would defer and return normally) is refused
  with `user-error "Starting agent, please wait"` before sending; the
  review is untouched. Text typed at the shell prompt is not guarded and
  gets prepended.
- Session id via the public `agent-shell-session-id :shell-buffer`.

Decisions made here:
- The client plist has one slot beyond the ticket's list, `:project`
  (session → directory), so the cross-project path rule needs no
  agent-shell knowledge in the generic send path.
- The request body carries a `keymap` text property
  (`agent-shell-notes-request-map`, parent `markdown-mode-map`). A
  text-property map only shadows keys it binds, so it binds every
  printing ASCII key markdown-mode leaves unbound to
  `self-insert-command`, plus `C-c C-c` to send (markdown-mode's
  `C-c C-c` is a prefix). The newline before the body carries the
  properties and is `rear-nonsticky` for `read-only` only, so an empty
  body takes typing and the first character inherits the map.
- Edit mode (ticket 06 swaps the local map) draws the request body
  without the `keymap` property, so in edit mode `C-c C-c` commits
  everywhere and the body stays writable.
- The request body is read back from the buffer on every redraw
  (`agent-shell-notes--request-text`); there is no separate variable.
- Marks are intersected with the note list, so marks of deleted notes
  are ignored; with no live marks the note at point is sent.
- `w` renders with no target, so paths are relative to each note's
  project.
- After a successful send only `agent-shell-notes--last-target` is set
  and a message shown; removing/archiving and clearing marks and request
  are ticket 05. `C-u C-c C-c` is ticket 09.
- Sanitizing follows the bundle's regexp for snippet lines (leading
  blanks of a matching line are replaced by `> `). The mention rule is
  mine: an `@` with a word character after it and none before it becomes
  `＠`, in paths and snippets. I did not locate the bundle's mention
  function.
- `agent-shell-notes-style` exists with the one value `claude`; the
  render function does not dispatch on it yet.

Verified: `make check` green (51 tests, evil test skipped). Mutations:
dropping the session-id guard and breaking the last-target band each
fail a test. No test starts an agent.

Unverified: picker order in the real completion UI (stubbed); the
rendered text through a real `agent-shell--prompt-send`; the mention
rule against the real bundle; evil normal state over the request body
(letters would still be evil commands there, see ticket 02).
