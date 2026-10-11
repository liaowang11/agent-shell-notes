---
title: Do source buffers show highlights in v1?
type: grilling
status: closed
assignee: claude
blocked-by: [002]
---

## Question

Highlights on the annotated source text are nice, not needed. ("Mark" now
means selecting a note in the review.) Decide for v1: no highlights,
highlights drawn once and allowed to vanish on refresh, or redrawn after
refresh. If any: what they look like and whether they show the note.

## Resolution

Grilled with Bill, 2026-10-11.

- **No highlights on source text in v1.** The review is the only place
  notes show. Reuse was checked first; it covers Magit only, and
  Magit-only highlights would make a missing highlight look like "no note"
  in transcripts and files.
- **Flash on jump**: `RET` in the review flashes the quoted range in the
  source with `pulse-momentary-highlight-region`. Nothing is stored; if the
  text moved, it flashes what is now at the saved positions, the same best
  effort as the jump.
- **Out of scope** for this effort, with the facts a later effort starts
  from (read from shallow clones, nothing run; agent-shell 70616c4a):
  - Magit: magit-review (MIT) `magit-review-locate-comment` and
    `--locate-in-file` / `--locate-at-line` / `--locate-by-content`
    (`magit-review-anchor.el:251-357`, about 190 lines with helpers) re-find
    a line by side and number, then by line text nearest the old line, from
    the section tree. Redraw needs `magit-refresh-buffer-hook` and `:after`
    advice on `magit-section--opportunistic-wash` (hunks washed later).
  - Transcript: no reusable code. Attach points:
    `agent-shell-section-functions` (`agent-shell.el:301`, run at `:7641`),
    `agent-shell-ui-post-expand-fragment-at-point-hook`
    (`agent-shell-ui.el:42`), and advice on
    `agent-shell--render-view-fragment` (`agent-shell.el:7361`) and
    `agent-shell-viewport--initialize` (`agent-shell-viewport.el:642`).
    Transcript quotes are Markdown, the buffer shows rendered text, so a
    search needs a rendered snapshot.
  - Files: annotate.el would bring its own store; own overlay code is
    about 40 lines. ai-code-interface hides a note on any hunk change;
    collab-comments' `collab-comments--locate` is GPL-3; org-remark is tied
    to its Org file.
