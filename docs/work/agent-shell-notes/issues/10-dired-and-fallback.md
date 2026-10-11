---
title: Capture from dired and from any other buffer
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [004]
---

## What to build

The `dired` source and the generic fallback, plus the ordered sources
option a user extends. Design: §4.1, §8.1 (dired and fallback sentences).

## Acceptance criteria

- [x] Dired: marked files, else the file at point; with a region, the files on its lines; paths only, grouped by directory in the review.
- [x] Fallback: region or current line, recording buffer name, major mode, line range and project.
- [x] `agent-shell-notes-sources` is an ordered list; a test adds an entry before the fallback and it wins for its mode.
- [x] `claude` renders ``About `a.el`, `b.el`:`` and ``In buffer `*Help*` (help-mode) at lines S-E:`` with the quote; golden files for both.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)

## Comments

### claude, 2026-10-12

Commits: a587d69 (dired capture), 1c0c241 (review groups dired by
directory), 0786028 (claude dired block), 302155f (fallback capture and
review), 2aea869 (claude fallback block), a4463e7 (sources-order test).

Seams tested (from the ticket and §11, not confirmed with Bill):
`agent-shell-notes-capture` in a real `dired-noselect` buffer and a
file-less `help-mode` buffer, asserted on `agent-shell-notes--notes`;
the review's `-group`/`-id`/`-field` text properties;
`agent-shell-notes--render` against hand-written golden files
`claude-dired.txt` and `claude-fallback.txt`.

Decisions:
- Default `agent-shell-notes-sources` is `dired`, `file`, `buffer`;
  07/08 put `transcript` and `magit` in front. `buffer`'s predicate is
  `always`.
- Dired: with a region, walk its lines (the existing `--line-extent`)
  with `dired-get-filename`, skipping `.`/`..` as dired's own region
  marking does; marks are ignored then. Else `dired-get-marked-files`
  (marked, else at point). No file: `user-error "No file at point"`.
  `:directory` is `default-directory`, so files in an inserted subdir
  group under the top directory. Markers cover the captured lines.
- Dired paths in `claude` are relative to the note's project (absolute
  for another project), each sanitized like a file path. Empty text
  ends the block at the `About ...:` line. In the review, the group
  heading is `# <dir relative to project> — <project>` and the note's
  location line lists the names relative to that directory.
- Fallback location `(:buffer NAME :mode MODE :start S :end E)`. The
  `claude` fence says `text`: there is no file, and a mode name
  (`help`, `fundamental`) is not a language. One line reads `at line N`,
  like file blocks. The buffer name goes through the path sanitizer.
- The review, popup and `claude` treat any unknown `:source` as a
  `buffer` note (`_` arms), so a user entry should return a
  buffer-shaped location (the defcustom doc says so; the test reuses
  `agent-shell-notes--buffer-extract`). 07/08 must add their arms above
  the `_` arms when merging.
- `--note-path` gained an optional FILE argument for dired's several
  files.

Verified: `make check` green (64 tests, evil test skipped).

Unverified: the dired region walk with `dired-hide-details-mode` or an
inserted subdirectory; dired over TRAMP; the sources-order test was not
mutated to watch it fail (it is a characterization test: the ordering
mechanism existed since ticket 02). Jumping to dired/fallback notes is
ticket 11.
