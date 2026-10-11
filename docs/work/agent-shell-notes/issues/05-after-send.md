---
title: After-send modes and restore-last
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [004]
---

## What to build

What a successful send does to the notes that went out, and one level of
undo for it. Design: §7, §5.2 (`x`, `C-c C-r`).

## Acceptance criteria

- [ ] `agent-shell-notes-after-send` picks `remove` (default), `archive` or `keep`; `agent-shell-notes-set-after-send` changes it for the session.
- [ ] `archive`: notes stay in place, dimmed, tagged `sent to <session>`; resending updates the tag; `t` skips archived notes; `x` purges them without asking.
- [ ] Marks clear after every send in every mode; the request goes with every send and clears after it; `w` applies none of this.
- [ ] `agent-shell-notes-restore-last` (`C-c C-r` and global) restores positions under `remove`, old tags under `archive`, and marks and request in every mode; a second call with nothing stored signals `user-error`.
- [ ] A failing send leaves everything unchanged.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)
