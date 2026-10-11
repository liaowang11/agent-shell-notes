---
title: send-all and the live round trip
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [005, 009]
---

## What to build

`agent-shell-notes-send-all` sends every unarchived note without opening
the review, and `make live-check` proves the whole path against a real
claude-agent-acp session. Design: §6.5, §11 (live).

## Acceptance criteria

- [ ] `send-all` ignores marks, sends every unarchived note with the request, applies after-send, restore-last and clearing like `C-c C-c`; `C-u` fills the compose buffer; no unarchived notes signals `user-error` before the picker; no live shell signals the same error as `C-c C-c`; a client without `:compose` errors on `C-u`.
- [ ] The review buffer, if live, is redrawn after `send-all`.
- [ ] `make live-check` (outside `check` and CI) starts a real session through agent-shell, sends a two-note review and asserts the transcript's user prompt equals the rendered `claude` text, then fills the compose buffer after an existing draft and asserts its content; no assertions on model output.

## Blocked by

- [After-send modes and restore-last](05-after-send.md)
- [Fill the target's compose buffer instead of sending](09-compose.md)
