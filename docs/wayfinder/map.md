---
title: agent-shell notes, from the ground up
label: wayfinder:map
---

## Destination

A new `DESIGN.md` that an implementation session can build from with nothing
left to decide: how notes are captured from Magit diffs, files and
agent-shell transcripts, where they collect, and how marked notes reach a
target session (agent-shell supported natively; other clients pluggable).

## Notes

- Domain: an Emacs package on top of agent-shell (Bill's fork) and Magit.
- Start from the idea, not from the existing `DESIGN.md` or `docs/plan.html`.
  Treat them as prior art. `docs/research/` stays valid as a fact base
  (package survey, agent formats, agent-shell and Magit API notes).
- Grilling tickets: grill Bill one question at a time; the agent never
  answers for him.
- Settled in the charting session (2026-10-11):
  - Both workflows matter equally: reviewing the agent's last turn, and a
    broader pass across files, diffs and sessions.
  - Notes go out as one batch after a pass, not one by one.
  - The batch is plain text. Bill can edit it or send it as is.
  - Capture is a small popup, org-capture style: quote and location filled
    in, type the note, `C-c C-c` appends and returns.
  - The review is a Markdown display; the wire text is rendered at send in
    a chosen style (superseded "what Bill sees is what is sent" on
    2026-10-11).
  - One global review; the target session is picked at send (superseded
    "one review per target session" on 2026-10-11).
  - Highlights on the source text are nice, not needed. The review is the
    source of truth.
  - Jumping from a note back to its source is best effort.
  - No persistence across Emacs restarts (from the earlier session).

## Decisions so far

- [Can agent-shell's compose buffer hold a review?](tickets/001-compose-buffer-facts.md): one shared, name-linked, text-mode draft per session that other commands overwrite and that cannot be appended to without focus; `agent-shell--prompt-send` sends text without it.
- [Review buffer: own buffer or the session's compose buffer](tickets/002-review-buffer.md): a package-owned Markdown review buffer per target session (per-session part superseded below); send, copy-and-discard or discard; sending goes through a customizable resolve-target + send seam, agent-shell the only v1 client.
- [When a review picks its target session](tickets/003-target-session.md): capture binds no target; one global, dired-style review where `S` sends marked notes to a session picked at send time, across all projects; supersedes the per-session part of the review buffer decision.
- [What one captured note looks like](tickets/004-entry-format.md): notes are data rendered at send in a `claude`, `codex` or `omp` style copied from each app; the review is a grouped, sorted display with a wdired-style edit mode and a request section; `C-c C-c` sends, `C-u C-c C-c` fills the compose buffer, `RET` on a location jumps.
- [How the capture popup behaves](tickets/005-capture-popup.md): ordered source types (transcript, Magit, dired, file, generic fallback); region or current line, transcript regions quote across blocks; `claude` sentences per block kind and `your last reply`; bottom popup, insert state, `C-c C-c` / `C-c C-k`, one at a time.
- [What happens to a review after it is sent](tickets/006-after-send.md): an `after-send` defcustom picks `remove` (default), `archive` (dimmed, tagged `sent to <session>`, resendable, `x` purges) or `keep` for send and compose; `w` never removes; marks and request clear after every send; one-level restore-last.
- [Do source buffers show highlights in v1?](tickets/007-source-marks.md): no highlights; `RET` in the review flashes the quoted range with `pulse-momentary-highlight-region`.
- [Confirm the Claude desktop diff-comment template from a real session](tickets/008-confirm-claude-template.md): diff template confirmed (`line N`, language-tagged fence); notes on the target's own transcript use Claude's native `<!-- reply N -->` quote blocks, first in the batch.
- [What the package and its symbol prefix are called](tickets/009-package-name.md): `agent-shell-notes` everywhere (package, prefix, repo, clone), repo rename at the start of implementation; no alias prefix; living docs say "agent-shell notes".
- [Which entry commands and bindings ship, and what Doom adds](tickets/010-entry-bindings.md): global commands `capture`, `review` and `send-all` (all unarchived notes to a picked session, `C-u` fills compose); no bindings outside the package's own buffers; Doom-agnostic.
- [How the package is tested](tickets/011-test-strategy.md): batch ERT with the real agent-shell fork and real Magit, only the process boundary stubbed; golden files per style for rendering, behavior assertions for the review; a hand-run `live-check` round trip; GitHub Actions `make check` on Emacs 29.1 and snapshot.
- [What happens to the old DESIGN.md and plan.html](tickets/012-old-design-docs.md): the new `DESIGN.md` overwrites the old in one commit that also deletes both plan HTML files; only re-checked facts and still-relevant open checks carry over; a pointer line names the old file's last SHA.

## Not yet specified

None: the last fog graduated into tickets on 2026-10-11.

## Out of scope

- Persistence across Emacs restarts.
- Reliable re-anchoring of notes after Magit refresh or transcript re-render.
- Highlights on source text: they need that re-anchoring, and only Magit has
  reusable code (magit-review, MIT); facts and attach points in
  [Do source buffers show highlights in v1?](tickets/007-source-marks.md).
- difftastic buffers, PDFs, plans as artifacts.
- Doom configuration (leader and localleader keys, `set-popup-rule!`
  entries): Bill's config, not the package, per
  [Which entry commands and bindings ship, and what Doom adds](tickets/010-entry-bindings.md).
- Notes written by the agent, MCP tools, parsing the agent's reply, threads.
