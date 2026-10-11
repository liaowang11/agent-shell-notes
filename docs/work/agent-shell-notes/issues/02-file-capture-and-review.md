---
title: Capture a note from a file and see it in the review
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [001]
---

## What to build

Bill selects lines in a file (or puts point on one), runs
`agent-shell-notes-capture`, writes a remark in the popup, saves, and
opens `agent-shell-notes-review` to see the note under its file heading.
Design: §3, §4.1 (`file` source only), §4.4, §5.1 (display, grouping,
folding), §5.2 (`n p g q TAB`).

## Acceptance criteria

- [x] Notes are stored in one global in-memory list with the data model of §3; nothing is read back from buffers.
- [x] The popup shows the read-only location and quote (folded after 6 lines), takes the note below, `C-c C-c` saves (empty text saves a quote-only note), `C-c C-k` aborts without asking, the window configuration is restored on close.
- [x] A second capture while the popup is open switches to it.
- [x] Evil insert state on open when evil is loaded; the test skips when evil is absent.
- [x] The review groups notes by file + project, orders groups by first capture, notes by line; a new note lands in place while the review is open.
- [x] `n`/`p` move between notes, `TAB` folds and unfolds a quote, `g` redraws, `q` quits.
- [x] Tests assert note data and review text properties, not display strings.

## Blocked by

- [Stand up the package and test harness](01-harness.md)

## Comments

claude, 2026-10-11. Commits: feb9b4c (line capture), b27938c (region),
bad4a66 (popup layout, abort, quote-only tests), 2788f3f (second capture
switches), ad96728 (popup fold + TAB), d1ec097 (review drawn from the
list), 6402a22 (live redraw on save), ab6f01f (`n p TAB g q`), 7c778e4
(evil), bbd80c0 (cleanup), 52d3010 (a review window shown elsewhere
keeps its note when a capture redraws it).

Seams tested (picked from §11, not confirmed with Bill):
`agent-shell-notes-capture` plus popup `C-c C-c`/`C-c C-k`, asserted
against `agent-shell-notes--notes`; `agent-shell-notes-review` plus the
review keys, asserted against the `agent-shell-notes-id`, `-field` and
`-group` text properties and `invisible-p`.

Verified: `make check` green (19 tests; the evil test skips under
`emacs -Q`). The evil test passes when evil's straight repo is added with
`-L` (run by hand). In batch the popup splits below the source (2 windows),
so the window-restore assertions are real.

Assumptions: a file quote is whole lines; a region ending at column 0 does
not include that line. `agent-shell-notes-sources` holds only `file`; a
buffer without a file gets `user-error` until ticket 10 adds the fallback.
`n`/`p` past the last/first note signal `user-error`. The review has no
`# Request` section yet. The redraw calls `remove-overlays`, so ticket 03
must re-apply mark overlays inside the draw. The review fence has no
language tag (the language table belongs to rendering, ticket 04).

Unverified: `C-c C-c` from evil insert state in a live Doom session (batch
checks only `key-binding`); the folded `...` display in a GUI frame.

Open (design gap, not this ticket): under evil, normal state in the
review shadows `n p g q TAB`. The design names evil only for the popup.
Checked: markdown-mode binds only `TAB` (no `<tab>`), so the `TAB` binding
also works in a GUI frame.
