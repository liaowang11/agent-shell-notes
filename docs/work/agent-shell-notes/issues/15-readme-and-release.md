---
title: README and release hygiene
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [011, 012, 013, 014]
---

## What to build

A README that lets someone install and use the package, and a clean
release state. Design: §2 (bindings suggested, Doom-agnostic), §10.

## Acceptance criteria

- [x] README: what it does, install, the three entry commands with suggested bindings, the review and popup keys, the options from §10, a note that Doom popup rules and leader keys are the user's config.
- [x] Commentary header matches the README's summary.
- [x] `checkdoc` clean; byte-compile clean on Emacs 29.1 and snapshot in CI.
- [x] Every option and face in §10 exists with a docstring.

## Blocked by

- [Jump from the review back to the source](11-jump.md)
- [The codex style](12-codex-style.md)
- [The omp style](13-omp-style.md)
- [send-all and the live round trip](14-send-all-and-live-check.md)

## Comments

claude, 2026-10-12. Commits: ac184e3 (checkdoc: capitalize Dired, name
every argument in three render docstrings), c7d8738 (README.md), df5330a
(Commentary matches the README summary). Doc-only changes, so no TDD.

Decisions:
- README sections: summary, requirements, install (`package-vc-install`,
  Doom `package!` recipe), the three entry commands with suggested
  `C-c n c/r/s` bindings, the three other global commands, capture
  sources, popup keys, review keys, edit-mode keys, sending, the nine
  options, four faces, the client plist (all seven slots, `:project` and
  `:turn-count` included), a Doom section saying leader keys,
  `set-popup-rule!` and evil choices are the user's config (with an
  example), known limitations, development.
- Requirements say the package uses agent-shell internals and is tested
  against liaowang11/agent-shell and acp.el (the forks CI clones);
  upstream agent-shell is untested.
- Known limitations, from earlier tickets: agent-shell-vertico re-sorts
  the picker; evil normal state shadows the review keys; text typed at
  the shell prompt gets prepended; `M-x agent-shell-notes-edit-mode`
  while editing drops edits; restore-last keeps one level and may land a
  note one place off; dead-source jumps for transcript, buffer, old-side
  and committed notes report an error.
- Development notes the `make live-check` prerequisites and that golden
  files carry significant trailing spaces (`claude-reply-escape.txt`,
  `claude-mixed-batch.txt`).

Verified: `checkdoc-file` on `agent-shell-notes.el` reports nothing
(Emacs 31.1.50); `make check` green (143 tests, evil test skipped); every
backticked `agent-shell-notes-*` symbol in the README (32) is defined in
the .el; every key listed matches the capture, review and edit-mode
keymaps; all nine §10 options and four faces exist with docstrings.

Box 3 left unticked: checkdoc and local byte-compile are clean (Emacs
31.1.50, warnings as errors), but CI has not run since the harness (last
run 38149473269, 2026-10-11). None of tickets 02-15 has been through CI,
so Emacs 29.1 and snapshot are unverified, including `json-serialize` on
29.1 (ticket 12). It needs Bill to push main. No Emacs 29 was available
locally.

Unverified: upstream agent-shell compatibility; the Doom snippet in the
README was not run; `make live-check` (ticket 14) awaits a fresh Claude
login.

### Code review fixes

claude, 2026-10-12. One commit per finding (or small group):
1. Mention rule only in paths: 6f10592 (also `--trim-lines` in
   `--claude-snippet`, finding 8). `claude-sanitize.txt` now keeps
   `cc @bill` in the quote; new test for `@decorator` and `,@body`.
2. omp nil `:turn`: e4c84ca. Heading `# Feedback on Assistant message`,
   never "last reply"; recorded on ticket 13.
3. Review quote fence names the file's language (`text` without a
   file): 3aaa48c. The capture popup uses the same function.
4. Note commands (`n`, `p`, `m`, `u`, `k`, `e`, `TAB`) refuse the
   request body with "Point is in the request": 5d6c889. Send, copy and
   jump keep their own errors.
5. DESIGN §6.2 `:project` row: dd0fa47.
6. Stubs of `agent-shell-viewport--buffer` and `agent-shell--turns`
   removed; the turn-count test uses a real three-turn transcript:
   f28a61a. §11 unchanged.
7. Magit review test asserts the group heading run and face runs in the
   location field: 0b5abeb.
8. `--own-session-p`, `--line-range` (under `--range-string`, codex
   `Lines:`, the omp heading), `--directory` moved up and used in
   `--note-path` and `--codex-workspace`, codex file path via
   `--note-path`, one heading format in `--group-heading`: fea3750.
9. `--other-session-quote`, `agent-shell-notes--request-map`: db17299.

Goldens are byte-identical after 6f10592. `make check` green.

CI green on Emacs 29.1 and snapshot at b202cf5 (run on 2026-10-12). The
first run after the push failed 2 dired tests on both versions: on the
runner the temp dir is under `$HOME`, so dired's `default-directory` is
abbreviated to `~/`. The tests now compare expanded directories; the
package already stored expanded paths. Reproduced and verified locally
with `TMPDIR` under `$HOME`.
