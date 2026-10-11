---
title: Edit and delete notes in the review
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [002]
---

## What to build

A wdired-style edit mode for note texts, and deletion keys. Design: §5.3,
§5.2 (`e`, `C-c C-e`, `C-x C-q`, `k`, `D`).

## Acceptance criteria

- [ ] `C-c C-e` and `C-x C-q` enter edit mode; `e` enters it with point in the note at point.
- [ ] Only note texts (and the request) are editable; headings, locations and quotes stay read-only.
- [ ] `C-c C-c` commits every changed text to the notes and leaves edit mode; `C-c C-k` reverts and leaves.
- [ ] Emptying a text keeps the note as quote-only.
- [ ] Mark and navigation keys are inactive in edit mode; the mode line shows `Edit`.
- [ ] `k` deletes the note at point without asking; `D` deletes marked notes after confirmation (uses marks when present, otherwise skip that case until marks land).

## Blocked by

- [Capture a note from a file and see it in the review](02-file-capture-and-review.md)
