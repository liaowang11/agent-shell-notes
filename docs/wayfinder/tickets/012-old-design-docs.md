---
title: What happens to the old DESIGN.md and plan.html
type: grilling
status: closed
assignee: claude
blocked-by: []
---

## Question

The new `DESIGN.md` replaces the old one and `docs/plan.html` (with
`docs/plan.packed.html`). Decide their fate: delete them and rely on git
history, move them under `docs/` as superseded prior art, or keep parts of
the old `DESIGN.md` (sections still true, such as facts it rests on) in
the new one.

## Resolution

Grilled with Bill, 2026-10-11. Facts checked: only the map and the tickets
on package name, test strategy and this one mention the old docs; most of
the old `DESIGN.md` covers anchoring, relocation, overlays and redraw,
all out of scope now.

- **Old `DESIGN.md`**: the new `DESIGN.md` overwrites it at the same path;
  the old text lives only in git history, no `docs/prior-art/` copy.
  Facts the new design relies on (the Magit and transcript API calls,
  with file:line references) are re-checked and rewritten where they are
  used, never copied wholesale. Anchors, relocation, overlays and the
  performance section are dropped.
- **`docs/plan.html` and `docs/plan.packed.html`**: deleted; no HTML plan
  for the new design. `DESIGN.md` is the only design artifact.
- **Pointer**: one line near the top of the new `DESIGN.md`: it supersedes
  the earlier design, `git show <sha>:DESIGN.md`, where `<sha>` is the last
  commit that touched the old file (`0e6b22c` as of this resolution).
  Closed tickets keep their wording.
- **Timing**: one commit, in the session that writes the new `DESIGN.md`:
  overwrite plus both deletions. Until then the files stay as prior art.
- **Open checks**: the new `DESIGN.md` re-states the old checks that still
  apply in its own checks-before-coding list (for example, viewport text
  keeping `agent-shell-ui-state` at runtime; the popup under evil and Doom
  popup rules); checks tied to out-of-scope work (overlay priority over
  Magit highlights, redraw on section hooks) are dropped.
