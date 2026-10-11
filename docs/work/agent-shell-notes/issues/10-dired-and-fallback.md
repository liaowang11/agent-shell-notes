---
title: Capture from dired and from any other buffer
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [004]
---

## What to build

The `dired` source and the generic fallback, plus the ordered sources
option a user extends. Design: §4.1, §8.1 (dired and fallback sentences).

## Acceptance criteria

- [ ] Dired: marked files, else the file at point; with a region, the files on its lines; paths only, grouped by directory in the review.
- [ ] Fallback: region or current line, recording buffer name, major mode, line range and project.
- [ ] `agent-shell-notes-sources` is an ordered list; a test adds an entry before the fallback and it wins for its mode.
- [ ] `claude` renders ``About `a.el`, `b.el`:`` and ``In buffer `*Help*` (help-mode) at lines S-E:`` with the quote; golden files for both.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)
