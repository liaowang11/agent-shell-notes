---
title: Jump from the review back to the source
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [007, 008, 010]
---

## What to build

`RET` or a click on a location line or group heading shows the source and
flashes the quoted range, best effort. Design: §9.

## Acceptance criteria

- [x] Live source buffer with valid markers: shown, point at the marker, range pulsed.
- [x] Magit or file note with a dead buffer: the worktree file is visited at the new-side start line; old-side and committed notes signal `user-error`.
- [x] Dired note: the directory is opened at the first file.
- [x] Transcript or fallback note with a dead buffer: `user-error "Source buffer is gone"`.
- [x] On a group heading, jumps to the group's first note.
- [x] Tests cover every source kind.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)

## Comments

Commits: 2dc1748 (claim), 9403b60 (live source, dead file), db9663e
(Magit), e6085bb (dired, transcript, fallback), 21e5fb8 (mouse-1,
group headings).

- `RET` and `<mouse-1>` in the review map run `agent-shell-notes-jump`.
  The target is decided at the start of the line: a `location` field
  gives its note; an `agent-shell-notes-group` heading gives the first
  note drawn after it (the group's first in display order). Elsewhere
  `RET` signals `user-error "No note source at point"`; a click only
  moves point (`mouse-set-point` runs first), so clicks in quotes,
  texts and the request body behave as before. Edit mode swaps the
  local map, so neither key jumps there.
- Live means the marker buffer is live and the start marker still
  belongs to it: `pop-to-buffer`, point at the start marker,
  `pulse-momentary-highlight-region` over the markers. This covers
  every source, dired included.
- Dead buffer (`agent-shell-notes--jump-dead`): `file` and new-side
  `magit` (staged and mixed included) `find-file-noselect` the worktree
  file and flash lines `:start`..`:end` (widened); old-side and
  `committed` Magit notes signal a `user-error` saying why; `dired`
  pops `dired-noselect :directory` and `dired-goto-file`s the first
  file; `transcript`, `buffer` and any user source fall to the `_` arm,
  `user-error "Source buffer is gone"`. New source arms go above `_`.

Verified: `make check` green (115 tests, evil test skipped). Every
source kind is jumped to, live and dead, through the review key;
pulses are recorded by stubbing `pulse-momentary-highlight-region`.

Unverified: the real flash and a real mouse click in a GUI frame (the
click test builds the event by hand, since batch never redisplays); a
transcript note captured in a viewport whose viewport buffer died while
the shell lives reports the buffer gone rather than jumping to the
shell; files over TRAMP.
