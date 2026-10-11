---
title: Capture from a Magit diff
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [004]
---

## What to build

Capture in Magit status, diff and revision buffers, with the review tags
and the `claude` diff rendering. Design: §4.2, §5.1 (tags), §8.1 (diff
notes).

## Acceptance criteria

- [ ] Region inside a hunk captures its lines; no region captures the line at point; point on `@@` captures the whole hunk; point on a file heading signals `user-error`.
- [ ] A region across hunks in one file makes one note with every touched hunk stored whole; across files signals `user-error`.
- [ ] Side is `new` unless every line is a deletion; mixed selections are `new` with the mixed flag; line numbers come from Magit's hunk-line mapping, not from parsing `@@`.
- [ ] The quote keeps every selected line with its prefix; type is staged / unstaged / committed with the revision.
- [ ] Review shows the bold range and tags (`staged`, `unstaged`, `commit <rev>`, `before changes`).
- [ ] `claude` renders `at line N` / `at lines S-E`, ` (before changes)` on the old side, prefixes stripped, a mixed selection keeping only its new-side lines; golden files for diff, old side and mixed.
- [ ] Tests build real Magit buffers on a temporary git repo.
- [ ] §12 check 4 (hunk-line on a partially hidden status hunk) is answered in the ticket's comments.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)
