---
title: The omp style
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [007, 008, 010]
---

## What to build

`agent-shell-notes-style` set to `omp` renders every source kind in
oh-my-pi's `/annotate` paste formats. Design: §8 shared rules, §8.3.

## Acceptance criteria

- [x] Diff notes: `## Code Review Annotations`, the verbatim preamble line, `### path — new S-E` (or `old`), `Path:` (absolute when the project differs), one `Hunk:` line per stored hunk, the selected lines with prefixes in a `diff` fence, the text; no `Occurrence:`.
- [x] Own-session transcript notes: `# Feedback on your last reply` when the note's turn equals the target's turn count at render, else `# Feedback on Assistant message N`; `## N. Feedback on:` with the quote inline in quotes or in a `text` fence when it holds a newline or backtick.
- [x] File notes `# Feedback on <path>`, dired `# Feedback on a.el, b.el`, fallback `# Feedback on <buffer>`, all with the `## N.` shape; other-session quotes plain.
- [x] Review order, numbers across the send, request after one blank line.
- [x] Golden files for the same case list as the codex ticket.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)

## Comments

claude, 2026-10-12. Commits: 291c265 (dispatch, diff notes), e398b16
(transcript notes; send passes the target's turn count), e737cad (file,
dired, fallback), b3bf173 (batch, cross-project, request goldens),
40432f4 (merge main).

Seams tested (picked from §11 as in ticket 04, not confirmed with Bill):
`agent-shell-notes--render` against `tests/golden/omp-*.txt` with
`agent-shell-notes-style` let-bound; `C-c C-c` through the stubbed
agent-shell boundary for the turn count.

Decisions made here:
- Dispatch: `agent-shell-notes--render` is a `pcase` on the style with an
  `'omp` arm and a `_` arm calling the old body, now
  `agent-shell-notes--claude-render`. The codex ticket adds one arm there.
  Per-note dispatch in `agent-shell-notes--omp-note` has `magit`,
  `transcript` (own, then other), `file`, `dired` arms above the `_`
  (buffer) catch-all.
- `--render` gained `&optional turn-count`; the send path (shared with
  send-all) passes the client's `:turn-count`, so a custom client must
  have that slot, as its docstring already said. Copy passes none; with
  no session id every transcript note is an other-session quote.
- `agent-shell-notes-set-style` is not added here: it is ticket 12's
  criterion.
- Headings: consecutive notes with the same heading string share it (a
  run of diff notes shares `## Code Review Annotations`; own-session
  notes share by turn; file by path; dired by names; fallback by buffer).
  Other-session quotes open none.
- Numbers count only `## N.` items (diff notes carry no number in omp),
  across headings, from 1 on every render.
- Dired has no quote, so it uses omp's `## N. General feedback`. An empty
  note text drops the text line.
- Quotes in `## N. Feedback on:` are trailing-trimmed per line; a newline
  or backtick sends them to a `text` fence (omp's rule, also for file
  notes, not the file-language fence). The diff fence keeps the whole
  quote with prefixes, `\ No newline` lines included.
- Joins follow the rendered samples in `omp-claude.md`, not the raw
  template: no blank between items or between `###` notes; one blank
  between heading sections and before the request. Several `Hunk:` lines
  are consecutive, one per `:hunks` entry (its first line).
- A transcript note spanning turns is named by its `:turn`.

Verified: `make check` green after merging main (120 tests, evil test
skipped). Mutation: counting diff notes as numbered fails two goldens.
The batch, cross-project and request goldens passed on first run (the
behavior was built by earlier slices).

Unverified: how omp's agent reads our ranges (`new 42-43`) and several
`Hunk:` lines, both ours; the text through a real
`agent-shell--prompt-send`; the "your last reply" heading against a real
shell's `agent-shell--turns` during a streaming turn.

claude, 2026-10-12, code review fix. A transcript note captured before
the first prompt has `:turn nil`; the heading used `%d` on it and
raised. Such a note is never the last reply (even against a target
with no turns) and gets `# Feedback on Assistant message`, no number,
as `--turn-string` drops the turn from the review location. Notes
sharing it still share the heading. Test:
`agent-shell-notes-render-omp-reply-without-turn`.
