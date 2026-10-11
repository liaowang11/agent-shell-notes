---
title: Capture from a Magit diff
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [004]
---

## What to build

Capture in Magit status, diff and revision buffers, with the review tags
and the `claude` diff rendering. Design: §4.2, §5.1 (tags), §8.1 (diff
notes).

## Acceptance criteria

- [x] Region inside a hunk captures its lines; no region captures the line at point; point on `@@` captures the whole hunk; point on a file heading signals `user-error`.
- [x] A region across hunks in one file makes one note with every touched hunk stored whole; across files signals `user-error`.
- [x] Side is `new` unless every line is a deletion; mixed selections are `new` with the mixed flag; line numbers come from Magit's hunk-line mapping, not from parsing `@@`.
- [x] The quote keeps every selected line with its prefix; type is staged / unstaged / committed with the revision.
- [x] Review shows the bold range and tags (`staged`, `unstaged`, `commit <rev>`, `before changes`).
- [x] `claude` renders `at line N` / `at lines S-E`, ` (before changes)` on the old side, prefixes stripped, a mixed selection keeping only its new-side lines; golden files for diff, old side and mixed.
- [x] Tests build real Magit buffers on a temporary git repo.
- [x] §12 check 4 (hunk-line on a partially hidden status hunk) is answered in the ticket's comments.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)

## Comments

claude, 2026-10-12. Commits: 64064ab (hunk lines from a diff), 093d95b
(whole hunk, cross-file error, sides, types, renames), 3c23c23 (hidden
status hunk), 98bf253 (review grouping and tags), 0a026e4 (claude diff
rendering, golden files), 4a45755 (`agent-shell-notes-tag` face),
7506006 (line walk stops at the end of the buffer: a region to
point-max used to hang). Merges of main: 6775c7f (05, 09), 2983eb2
(10), fb4bf46 (08). In the merges, `magit` joins the `file` arm (above
the buffer catch-all) in `--group-key`, `--group-heading`,
`--location-string` and `--claude-block`; `--note-path`'s new FILE arg
falls back to `--note-file`. Sources order: transcript, magit, dired,
file, buffer. Changing those arms back to `'file` fails the popup,
review and golden diff tests.

Seams tested (picked from §11, not confirmed with Bill):
`agent-shell-notes-capture` driven in real Magit diff, revision and
status buffers on a temporary git repo (Magit 4.7.0, recipe from the
impl notes), asserting the saved note; the review draw asserting the
location line text and faces; `agent-shell-notes--render` against
`tests/golden/claude-diff{,-old-side,-mixed}.txt` from literal notes.

Decisions (where the impl notes and DESIGN §4.2 disagree, Magit's real
behavior wins):
- Line numbers always come from `magit-diff-hunk-line` on body lines.
  Point on `@@` selects every body line of the hunk and maps the first
  and last one, never the heading (on the heading Magit maps the first
  changed line, one too high on the old side). For a hunk this equals
  the `@@` ranges, so no range slot is read.
- New side: start and end come from the first and last selected line
  that is not `-`; Magit maps a `-` line to the next new line (selection
  `+3 changed`/` 4`/`-5` is 3-4, not 3-5). Old side only when every line
  is `-`, so no correction there.
- `\ No newline at end of file` lines stay in the quote but are ignored
  for side, mixed and numbers, and dropped at render. `@@` lines a
  region crosses are not selected lines and stay out of the quote; the
  hunks are in `:hunks`.
- `:hunks` is each hunk's `buffer-substring-no-properties` start..end,
  heading included, trailing newline kept.
- Crossing files = more than one file section among the touched lines
  (staged and unstaged copies of one file in status count as two).
  Errors: "Point is not in a hunk", "The region crosses files", "Merge
  diffs are not supported" (combined hunks, where hunk-line errors).
- `:type` is `magit-diff-type`; `committed` takes `magit-buffer-revision`,
  else `magit-buffer-diff-range`, as typed (`HEAD`), not resolved to a
  hash. `magit-diff-working-tree` therefore yields `committed`/`HEAD`
  and a `commit HEAD` tag although its new side is the worktree; left
  as Magit types it.
- Old side of a rename: `:file` is the file section's `source` (old
  path); the new side uses its `value`.
- `:file` stays relative (DESIGN table); `agent-shell-notes--note-file`
  expands it against `:project` for grouping, the popup and sent paths.
  In a Magit buffer `:project` is the repo top (asserted in a test).
- Magit and file notes on one file share a review group. Tags render as
  `` `tag` `` after the bold range in face `agent-shell-notes-tag`
  (defined here). In the merge of main (6775c7f) ticket 05's
  `sent to <session>` tag moved into `agent-shell-notes--tags`, so it
  takes the same face; its text is unchanged and 05's tests pass.
- The Magit predicate matches a `magit-section-mode` buffer with a hunk
  or file section at either end of the line extent; elsewhere in Magit
  (log lines) capture falls through to later sources.
- A region over a collapsed hunk counts its hidden lines as selected
  (buffer lines, as Magit counts them).

§12 check 4, answered by running it: in `magit-status`, with foo.txt's
hunk hidden (`magit-section-hide`, its text invisible), capture at a
hidden `+` line and over a hidden region gives the numbers of the diff
buffer (new 3; new 3-4 mixed). Hunk text is always in the buffer and
hunk-line counts buffer lines, so hiding does not matter.

Verified: `make check` green. Byte-compile with warnings as errors and
`require` with no Magit on the load path both work; the Magit predicate
then returns nil. Mutations: dropping the `-` line correction and the
rename `source` each fail a test.

Unverified: hunk-line after a `\ No newline` line in the middle of a
hunk (Magit counts it, off by one; not handled); merge diffs (refused);
stash buffers; capture under evil in a Magit buffer; the rendered text
through a real send.
