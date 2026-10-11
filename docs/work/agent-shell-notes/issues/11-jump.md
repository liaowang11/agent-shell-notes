---
title: Jump from the review back to the source
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [007, 008, 010]
---

## What to build

`RET` or a click on a location line or group heading shows the source and
flashes the quoted range, best effort. Design: §9.

## Acceptance criteria

- [ ] Live source buffer with valid markers: shown, point at the marker, range pulsed.
- [ ] Magit or file note with a dead buffer: the worktree file is visited at the new-side start line; old-side and committed notes signal `user-error`.
- [ ] Dired note: the directory is opened at the first file.
- [ ] Transcript or fallback note with a dead buffer: `user-error "Source buffer is gone"`.
- [ ] On a group heading, jumps to the group's first note.
- [ ] Tests cover every source kind.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)
