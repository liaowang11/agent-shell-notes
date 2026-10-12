---
title: Location and tag faces survive font-lock
status: open
labels: [ready-for-agent]
assignee: claude
blocked-by: []
---

## What to build

The review puts `agent-shell-notes-location` and `agent-shell-notes-tag`
on the location line and tags as `face` text properties. Font-lock (from
the Markdown parent mode) replaces them: after `font-lock-ensure` the
location `**line 1**` shows `markdown-bold-face`. Batch tests never run
font-lock, so this went unnoticed. Apply both faces with overlays, as the
archived face already is (`agent-shell-notes.el:1452`), in the review and
in the capture popup's location line. Design: §5.1, §10.

## Acceptance criteria

- [x] After `font-lock-ensure` in a drawn review, the location line and each tag show their package face (`get-char-property`, which sees overlays).
- [x] Same for the capture popup's location line.
- [x] Overlays are rebuilt on every redraw and do not leak (`remove-overlays` already runs in the draw).
- [x] Tests run real font-lock (`font-lock-mode`, `font-lock-ensure`) and fail on the current code.

## Comments

Found 2026-10-12 while checking Markdown highlighting in the review.

Claude, 2026-10-12, implementation.

- SHAs: ea52d88 claim; 86ce470 fix (code + tests); 4ae666e DESIGN §5.1,
  §10.
- Decisions:
  - New `agent-shell-notes--face-overlay` (evaporating overlay) carries
    the location face, each tag face (the separating spaces get none, as
    before) and the archived face. The archived overlay has priority 1 so
    an archived note's location and tags still dim; without it the
    nested location overlay wins (checked: the assertion fails at
    priority 0).
  - The test helper `--location-faces` now reads `get-char-property`
    runs, so the existing range-and-tags test checks the overlays too.
- Verified: both new tests failed first (the location came back as
  `**`/`line 7`/`**` runs of markdown faces; the popup line had no
  face). `make check` green (compile with error-on-warn, 158 pass, 2
  evil skips), also with `TMPDIR` under $HOME. Real font-lock runs in
  batch: `font-lock-ensure` repainted the text before the fix.
- Unverified: the look in a GUI frame (face merging of the archived
  overlay over the location overlay was checked through
  `get-char-property` only).
