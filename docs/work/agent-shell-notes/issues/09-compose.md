---
title: Fill the target's compose buffer instead of sending
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [004]
---

## What to build

`C-u C-c C-c` renders as a send would, then appends the text to the
target session's viewport compose buffer and switches there, so Bill can
edit before agent-shell sends. Design: §6.3, §6.2 (`:compose` slot).

## Acceptance criteria

- [ ] The client plist gains an optional `:compose`; the agent-shell client appends through the viewport show-buffer path with `:append`, `:edit t`, and the disposition read back from an existing viewport (no viewport created by the read).
- [ ] The text lands after an existing draft; the draft's queue/steer choice is preserved.
- [ ] After-send, mark clearing, request clearing and restore-last apply as for a send.
- [ ] A client without `:compose` gives a `user-error` naming the client and changes nothing.
- [ ] Tests run the real viewport show-buffer code with only its header and position helpers stubbed.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)
