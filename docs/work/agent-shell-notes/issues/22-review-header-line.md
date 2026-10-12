---
title: Review header line
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

A header line on the review buffer: mode label │ summary │ key hints, for
example:

```
Edit │ 3 notes · 2 groups · 1 marked │ C-c C-c save  C-c C-k revert
```

Design: §5.1 (header line), §5.3.

## Acceptance criteria

- [x] The label is `Review` or `Edit`; `Edit` uses a warning-like package face, `Review` a bold one.
- [x] The summary counts notes, groups, marked and sent (archived) notes, leaves out zero counts, uses singular and plural correctly, and shows `No notes` on an empty review. Edit mode shows the same counts.
- [x] Key hints come from `substitute-command-keys` against the mode's map: `C-c C-c send  C-c C-e edit` in the review, `C-c C-c save  C-c C-k revert` in edit mode.
- [x] Marking updates the header line without a redraw.
- [x] The ` Edit` mode-line lighter stays.

## Comments

2026-10-13 (claude): done.

Group noun: "groups". A review group is a file + project, a Dired
directory, a transcript turn + kind or a buffer, so "files" would be
wrong for three of the four. "sources" would clash with the Source term
(and the `:source` kind): two turns of one transcript are one source but
two groups. DESIGN §5.1 and the README already say "group", so no
GLOSSARY entry was added.

Live update: `header-line-format` is `(:eval
(agent-shell-notes--header-line))`, so every redisplay recomputes it
from the note list, the marks and `agent-shell-notes-edit-mode`.
Marking changes only overlays, so `agent-shell-notes--set-marks` also
calls `force-mode-line-update`. Faces are text properties on the label:
the overlay rule of §5.1 is about buffer text under font-lock, and the
header line is not fontified.

Key hints: `agent-shell-notes-edit-mode` and `-edit-commit` are each bound
to several keys and `substitute-command-keys` picked `C-x C-q`. Both now
carry `:advertised-binding` (`C-c C-e`, `C-c C-c`), which also changes the
edit-mode docstring's `\\[agent-shell-notes-edit-commit]` to `C-c C-c`.

Counts come from the note list, not the buffer. In edit mode a capture
is not drawn until edit mode ends, so the header counts it first.

Verified: four new tests (`agent-shell-notes-header-line-empty-review`,
`-counts-omit-zeros-and-pluralize`, `-follows-marks-without-redraw`,
`-switches-with-edit-mode`) failed on the old code, then passed.
`make compile`, `make test` (176 tests, 5 skipped) and `make test-ts`
(176 tests, 2 skipped) pass. Batch `format-mode-line` returns "", so the
tests evaluate the `:eval` form directly.

Unverified: the rendered header line in a live Emacs frame (faces,
redisplay after marking); batch only.
