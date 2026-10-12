---
title: Location and tag faces survive font-lock
status: open
labels: [ready-for-agent]
assignee:
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

- [ ] After `font-lock-ensure` in a drawn review, the location line and each tag show their package face (`get-char-property`, which sees overlays).
- [ ] Same for the capture popup's location line.
- [ ] Overlays are rebuilt on every redraw and do not leak (`remove-overlays` already runs in the draw).
- [ ] Tests run real font-lock (`font-lock-mode`, `font-lock-ensure`) and fail on the current code.

## Comments

Found 2026-10-12 while checking Markdown highlighting in the review.
