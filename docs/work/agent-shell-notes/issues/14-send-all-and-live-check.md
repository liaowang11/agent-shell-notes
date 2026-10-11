---
title: send-all and the live round trip
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [005, 009]
---

## What to build

`agent-shell-notes-send-all` sends every unarchived note without opening
the review, and `make live-check` proves the whole path against a real
claude-agent-acp session. Design: §6.5, §11 (live).

## Acceptance criteria

- [x] `send-all` ignores marks, sends every unarchived note with the request, applies after-send, restore-last and clearing like `C-c C-c`; `C-u` fills the compose buffer; no unarchived notes signals `user-error` before the picker; no live shell signals the same error as `C-c C-c`; a client without `:compose` errors on `C-u`.
- [x] The review buffer, if live, is redrawn after `send-all`.
- [x] `make live-check` (outside `check` and CI) starts a real session through agent-shell, sends a two-note review and asserts the transcript's user prompt equals the rendered `claude` text, then fills the compose buffer after an existing draft and asserts its content; no assertions on model output.

## Blocked by

- [After-send modes and restore-last](05-after-send.md)
- [Fill the target's compose buffer instead of sending](09-compose.md)

## Comments

claude, 2026-10-12. Commits: 23a9afe (send-all, shared send helper),
9f20795 (archived skip and refusal tests), 8d3adb8 (compose test),
312073e (live check), bfca757 (live check clean-up fix).

Seams tested (picked from §11, not confirmed with Bill): the global
command `agent-shell-notes-send-all` (with and without prefix) with
only the process boundary stubbed as in 04/05, plus the compose path
through the real viewport code as in 09. Live: `make live-check`.

Decisions:
- `agent-shell-notes-send` now hands its notes to a new
  `agent-shell-notes--send-notes (notes compose)`, which holds the
  compose guard, picker, render, client call, `--after-send`,
  last-target and message. `send-all` calls the same helper, so
  after-send, restore-last and clearing are shared, not copied.
- Notes go in review order (`--groups`), unarchived only. No notes:
  `user-error "No unarchived notes"`, raised before the compose-client
  check and the picker (same order as `send`).
- No review key (§5.2 lists none; §2 says no bindings). Autoloaded.
- With the review buffer dead, send-all sends with an empty request
  (tested).
- Live test (`tests/live/agent-shell-notes-live.el`): one shell started
  with `agent-shell--start` in a temp dir holding `sample.el`, so paths
  are relative. Notes are captured through the real popup. Step 1 marks
  notes 1 and 3 and runs `agent-shell-notes-send` from the review.
  Step 2 seeds a "my draft" compose buffer and runs `C-u`
  `agent-shell-notes-send-all` (DESIGN §11 says `C-u C-c C-c`; I used
  send-all to exercise this ticket's command over the same compose
  path). Expected text is a hand-written literal. Only
  `agent-shell--read-shell-buffer` is stubbed (it reads the
  minibuffer). Reads are auto-approved, everything else rejected.
  `turn-complete` is waited on but only reported as INFO, since the
  model's answer is not under test.

Verified: `make check` green (69 tests, evil test skipped). Mutations:
dropping the archived filter fails the skip test; dropping the empty
guard fails the skip and refusal tests; ignoring the prefix fails the
compose and refusal tests.

Live run (one attempt, sandbox off, real claude-agent-acp):

    timeout 600 make live-check

Output (trimmed): both assertions PASS ("the transcript's user prompt is
the rendered text": `input-submitted` prompt equal to the literal;
"the compose buffer holds the text after the draft"; "compose sent
nothing"). Then: `FAIL the turn completed / waited 180s for
turn-complete`, and during clean-up `Kill shell session too? (y or n)
FAIL the round trip ran / End of file during parsing: Error reading from
stdin`; `3 passed, 2 failed`, exit 2. The session transcript shows the
agent's only reply: `Failed to authenticate: OAuth session expired and
could not be refreshed`. So the prompt reached the agent intact, but
the Claude login has expired.

Box 3 is left unticked:
- bfca757 fixes both harness failures (kill the shell before the
  viewport, answer the viewport's kill prompt; turn-complete is INFO).
  It has not been re-run; it byte-compiles clean.
- A passing run needs a fresh Claude login (`claude` /login), then
  `timeout 600 make live-check` by hand.

Unverified / open:
- The live harness after bfca757.
- Whether the model's real reply arrives in time with a valid login
  (INFO only).

Later: e35c0bd and 8319ab3 merge main (08, 10, then 07); the test
conflict was add/add, both sides kept; `make check` green (109 tests,
evil skipped). 3301b3f also ends the wait on an ACP `error` event, so
a run with an expired login stops early instead of waiting 180 s (not
run; it byte-compiles clean). The auth failure in the run above may
have arrived as agent text rather than an `error` event; unknown.

`make live-check` passed on 2026-10-12 at 70d66b6 (`timeout 600`, sandbox
off): 3 passed, 0 failed, exit 0. The script fixes in bfca757 and 3301b3f
held: the login was still expired ("turn end: error: Authentication
required", reported as INFO), and cleanup finished without a prompt.
