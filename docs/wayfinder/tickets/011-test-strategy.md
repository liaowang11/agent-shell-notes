---
title: How the package is tested
type: grilling
status: closed
assignee: claude
blocked-by: []
---

## Question

The old `DESIGN.md` (section 9) planned batch ERT with stubbed agent-shell
core, real `agent-shell-ui.el` and real `magit-diff.el`, built mostly
around re-anchoring after redraw and refresh, which is now out of scope.
Decide the test strategy for the new shape: which parts get batch ERT
(capture per source type, review display and edit mode, rendering in the
`claude`, `codex` and `omp` styles, send and after-send), which real
dependencies load versus are stubbed, whether rendering uses golden
strings, and whether any test runs against a live agent-shell session.

## Resolution

Grilled with Bill, 2026-10-11. Prior art: agent-shell-side's `Makefile`
(`check`, `live-check`) and the agent-shell fork's GitHub Actions workflow
(`purcell/setup-emacs`, shallow-cloned dependencies). The fork is public.

- **Harness**: as agent-shell-side. `make check` byte-compiles with warnings
  as errors, then runs batch ERT under `emacs -Q` with `load-prefer-newer`.
  Tests live under `tests/`. Dependency directories are Makefile variables,
  listed in one place, shared by local runs and CI.
- **agent-shell is real**: tests load Bill's agent-shell fork and build
  transcript buffers with its real fragment rendering. Only the process
  boundary is stubbed (`agent-shell--prompt-send`, session lookup). No ACP
  process starts. Reason: transcript capture rests on private functions
  (block-id suffixes, `agent-shell--turn-position`,
  `agent-shell-markdown-reconstruct`), and stubs of those drift silently.
- **Magit is real**: diff buffers built in a temporary git repo. Cases:
  region inside a hunk, line at point, point on `@@`, a region across hunks
  (one note, every touched hunk), across files (`user-error`), staged and
  unstaged tags.
- **Rendering**: golden files `tests/golden/<style>-<case>.txt`, rendered
  from note data, not buffers, for `claude`, `codex` and `omp`. Cases: diff,
  file, reply in the target session, quote from another session, dired,
  fallback, request, mixed batch, cross-project workspace, per-send
  numbering.
- **Review buffer**: tests drive the real commands and assert behavior (note
  order, text properties, state), not the display string: grouping and
  order, in-place insertion, quote folding, edit mode (only note text
  editable, `C-c C-k` reverts), marks, `t`, `x`, the three after-send modes
  for send and compose, `w` leaving everything, request clearing,
  restore-last, a failed send changing nothing.
- **Capture popup**: call capture, insert text, save or abort; assert the
  stored note, quote-only save, one popup at a time, window layout restored.
  The evil insert-state test skips when evil is not on the load path.
- **Live**: `make live-check`, outside `check` and CI, run by hand. Starts a
  real claude-agent-acp session through agent-shell; `C-c C-c` a two-note
  review and assert the transcript's user prompt equals the rendered
  `claude` text; `C-u C-c C-c` and assert the compose buffer holds it after
  an existing draft. No assertions on model output.
- **CI**: GitHub Actions in v1, `make check` on push and pull request.
  Matrix: Emacs `29.1` and `snapshot`; the package declares
  `(emacs "29.1")`. CI shallow-clones the agent-shell fork at `main` head
  (no pin: breakage from a rebase should show), the acp fork, shell-maker,
  markdown-mode, and Magit with its dependencies (`magit`, `transient`,
  `with-editor`, `llama`, `compat`, `cond-let`), not package.el. No JUnit
  report workflow in v1.
- Supersedes the old `DESIGN.md` section 9 (stubbed agent-shell core,
  re-anchoring tests, deferred live check).
