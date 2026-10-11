---
title: The omp style
status: open
labels: [ready-for-agent]
assignee:
blocked-by: [007, 008, 010]
---

## What to build

`agent-shell-notes-style` set to `omp` renders every source kind in
oh-my-pi's `/annotate` paste formats. Design: §8 shared rules, §8.3.

## Acceptance criteria

- [ ] Diff notes: `## Code Review Annotations`, the verbatim preamble line, `### path — new S-E` (or `old`), `Path:` (absolute when the project differs), one `Hunk:` line per stored hunk, the selected lines with prefixes in a `diff` fence, the text; no `Occurrence:`.
- [ ] Own-session transcript notes: `# Feedback on your last reply` when the note's turn equals the target's turn count at render, else `# Feedback on Assistant message N`; `## N. Feedback on:` with the quote inline in quotes or in a `text` fence when it holds a newline or backtick.
- [ ] File notes `# Feedback on <path>`, dired `# Feedback on a.el, b.el`, fallback `# Feedback on <buffer>`, all with the `## N.` shape; other-session quotes plain.
- [ ] Review order, numbers across the send, request after one blank line.
- [ ] Golden files for the same case list as the codex ticket.

## Blocked by

- [Capture from a Magit diff](07-magit-capture.md)
- [Capture from an agent-shell transcript](08-transcript-capture.md)
- [Capture from dired and from any other buffer](10-dired-and-fallback.md)
