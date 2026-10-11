---
title: Capture from an agent-shell transcript
status: closed
labels: [ready-for-agent]
assignee: claude
blocked-by: [004]
---

## What to build

Capture in shell and viewport buffers, grouped by session, turn and block
kind, rendered in the `claude` style as Claude's native reply blocks when
sent to the note's own session. Design: §4.3, §5.1 (transcript groups),
§8.1 (reply blocks and other-session quotes).

## Acceptance criteria

- [x] Block kind comes from the fragment's qualified id (message, thought, tool, plan, prompt, permission, mixed); a region may cross blocks and turns, prompts and permissions included.
- [x] Turn index comes from the shell's turn position, or the viewport page cursor on a history page; the note records session id, shell name, turn and the prompt's first line.
- [x] The quote is the agent's Markdown via the copy-as-markdown reconstruction; capture during a streaming turn works.
- [x] Review groups by session + turn + kind, shows the turn index, never sends it.
- [x] `claude`: notes on the target's own session render as `<!-- reply K -->` blocks (K = block count, max 99, later blocks `<!-- reply -->`), `> `-quoted, text with 3+ newlines squeezed and `<!-- reply` escaped, placed first, two blank lines before the rest; other-session notes render as a plain quote and text. "Own session" is decided at render from the client's session id.
- [x] Tests render transcripts with the fork's real fragment code on a fake state, no ACP process.
- [x] §12 checks 1, 2, 6 and 7 are answered in the ticket's comments.

## Blocked by

- [Send a review to an agent-shell session in the claude style](04-send-claude.md)

## Comments

claude, 2026-10-12. Commits: e1782ce (capture in a shell), 649556d
(block kinds, turns, streaming), 616dc18 (viewport page), a65907e
(review groups), 5e8f249 (claude reply blocks, goldens).

Seams tested (picked from DESIGN §11, as ticket 04 did; not confirmed
with Bill): `agent-shell-notes-capture` in a fake shell built with the
fork's real `agent-shell--update-fragment` (03-transcript.md §7 recipe)
and in a real `[viewport]` buffer filled by `agent-shell-viewport--initialize`
(only `--update-header` stubbed), asserted on the saved note; the review
buffer's group headings and fields; `agent-shell-notes--render` against
goldens (`claude-reply-own-session` is DESIGN §8.1's worked example,
`claude-reply-other-session`, `claude-mixed-batch`, `claude-reply-escape`)
plus a 99-cap assertion; `C-c C-c` through the stubbed boundary, to the
note's own shell and to another.

Where DESIGN §4.3 and the fork disagree (03-transcript.md), I followed the
fork:
- Live user prompts are comint text, not `-user_message_chunk`
  fragments. Non-fragment text is `prompt` when it is the viewport's
  echoed prompt (`agent-shell-viewport-prompt`), the shell's prompt string
  (`comint-highlight-prompt`), or input before the next
  `shell-maker--marker` with no prompt string in between. Replayed
  `-user_message_chunk` entries are `prompt` too.
- Viewport turn: `(agent-shell-viewport--position)` `:current`, read from
  the cache without `:force-refresh` (`--page-cursor` is nil on the live
  mirror and stale after `view-last`). A viewport page is one turn.
- Session id: `agent-shell-session-id :shell-buffer`.
- Block ids are matched at the end of the qualified id, never by
  splitting on `-` (the namespace is the request count). Extra kinds:
  an activity-group header counts as `tool` (it heads tool calls);
  `<toolCallId>-plan` and session `plan` are `plan`; `permission-<id>` is
  `permission`; a tool call is a block id found in the shell's
  `:tool-calls`; other chrome (`starting`, `Error`, ...) has no kind.
  A region with no kind at all is `message`.
- Quote: `agent-shell--buffer-markdown-substring`, leading/trailing
  newlines trimmed. No turn `#` heading appears without chat mode
  (§12 check 6); none is needed, since the turn is never sent.

Wire details from Claude's bundle (`ve`/`_e`/`C`/`ye` in the cached
`e520191a…-DPH6Owwn.js`), where DESIGN's wording is looser:
- A reply block needs a non-empty comment (`j`). An own-session note with
  no text goes out as a plain quote and is not counted in K.
- Only a whole line `<!-- reply -->` / `<!-- reply N -->` in the text is
  escaped to `&lt;…`; an inline `<!-- reply` is left alone.
- Quote lines are `> ` + line, so an empty line is `> ` (trailing space
  kept); each source line is first trimmed at the end (DESIGN's shared
  rule). Reply blocks are joined by one blank line, two blank lines before
  the rest.
- Past 99 reply blocks Claude drops the rest from the reply set; here
  they go out as plain quotes after the other notes.

Other decisions:
- Extent: the region exactly (Claude quotes the selection), else the
  current line; not widened to whole lines as for files.
- `agent-shell-notes--render` takes an optional 4th arg, the target's
  session id; send passes the client's `:session-id`, `w` passes nil, so
  a copy renders every transcript note as an other-session quote.
- `:turn-end` is part of the group key; the heading reads `turns 1-2` for
  a region across turns. Within a group, notes keep capture order (they
  share a turn). With no turn history the turn is nil and the heading
  omits it.
- The review shows `**reply**` (kind `message`) and the `> ` quote; the
  prompt's first line is recorded but not shown.
- A viewport in compose (edit) mode is not a transcript source.

§12 checks:
1. Yes in batch: a viewport page filled by the real `--initialize` from
   `agent-shell--turn-at-index` carries `agent-shell-ui-state` (asserted).
   `agent-shell-markdown-source` and a live viewport are not checked.
2. No (03-transcript.md §4): `--page-cursor` is written only by
   `--show-page`, `--enter-compose-page` and `previous-page`; the position
   cache is used instead.
6. No (03-transcript.md §5): a region starting in a tool body gets no
   `###` heading for it, and turn `#` headings need chat mode.
7. Yes, from source (01-sending.md §1): fork and agent-shell-side shells
   are ordinary `agent-shell-mode` buffers, so `agent-shell-buffers`
   lists them; the fork has no "sidechat".

Verified: `make check` green; mutations (dropping the permission, plan,
group, prompt-text or user-message branches, `:turn-end`, the cache read
without `:force-refresh`, the session id in send, trim/escape/squeeze,
the 99 cap, the empty-comment filter) each fail a test. No test starts
an agent.

Unverified: a live shell and viewport (thought and group fragments come
from `--on-notification` live; tests call `--update-fragment` with
realistic block ids); `agent-shell-markdown-source` reconstruction (the
batch buffer has no rendered Markdown); the bundle's `e()` normalizer
inside `C` and the `t` transform in `be`, not traced; capture before any
prompt in a real shell.

Merges: 03f10f1 (main at 4fb95f4, tickets 05 and 09) and 9ac8141 (main at
be05623, ticket 10). The send path passes the target's session id for
both send and `C-u C-c C-c` compose, so compose renders own-session reply
blocks too. The own/other-session send test binds
`agent-shell-notes-after-send` to `keep`, since main's default `remove`
takes the note off before the second send. The `transcript` arms sit
above the `buffer` catch-all in all five dispatches (`--group-key`,
`--group-heading`, `--insert-note`, the popup header via
`--location-string`, `--claude-block`); removing any one fails an
existing test (review grouping, popup header, render goldens, send).
