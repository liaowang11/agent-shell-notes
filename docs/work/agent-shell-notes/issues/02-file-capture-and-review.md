---
title: Capture a note from a file and see it in the review
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [001]
---

## What to build

Bill selects lines in a file (or puts point on one), runs
`agent-shell-notes-capture`, writes a remark in the popup, saves, and
opens `agent-shell-notes-review` to see the note under its file heading.
Design: §3, §4.1 (`file` source only), §4.4, §5.1 (display, grouping,
folding), §5.2 (`n p g q TAB`).

## Acceptance criteria

- [ ] Notes are stored in one global in-memory list with the data model of §3; nothing is read back from buffers.
- [ ] The popup shows the read-only location and quote (folded after 6 lines), takes the note below, `C-c C-c` saves (empty text saves a quote-only note), `C-c C-k` aborts without asking, the window configuration is restored on close.
- [ ] A second capture while the popup is open switches to it.
- [ ] Evil insert state on open when evil is loaded; the test skips when evil is absent.
- [ ] The review groups notes by file + project, orders groups by first capture, notes by line; a new note lands in place while the review is open.
- [ ] `n`/`p` move between notes, `TAB` folds and unfolds a quote, `g` redraws, `q` quits.
- [ ] Tests assert note data and review text properties, not display strings.

## Blocked by

- [Stand up the package and test harness](01-harness.md)
