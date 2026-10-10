# Annotation models for coding-agent feedback

Research date: 2026-10-10. This extends the
[general package survey](01-package-survey.md). Checked primary
documentation and source; no packages installed, UI exercised or tests run.

## Conclusion

**Hunk-notes is the better starting point for Bill's code feedback.** It models
a review comment against a diff, provides real old/new source locations, saves
comments, tracks resolution and produces an agent prompt. Reviewer.el is useful
when the source is arbitrary prose or a response buffer and the notes are
temporary. Neither yet supplies a complete, durable human/agent review thread.

The useful design to borrow from oh-my-pi is **source snapshot → attached notes →
collected draft → explicit action**. A code diff, a plan and an agent response
need different anchors; they can still share collection and Agent Shell delivery.
This is a recommendation based on the source observations below, not an
implementation proposal requiring adoption of all surveyed features.

## Hunk-notes versus reviewer.el

| Concern | Hunk-notes | Reviewer.el |
| --- | --- | --- |
| Source | Unified diff; Git/JJ/VC/Magit adapters | Arbitrary text buffer, including files and Magit |
| Anchor | File, side, source ranges, change type, hunk header, nearby context | Live overlay start/end positions |
| Comment identity | ID plus repository/backend/revision metadata | Thread ID, author/time/status fields on an overlay |
| Scope | Line or range within one file and hunk | Region or word; can span prose |
| Editing/navigation | Multiline editor, next/previous, list, delete, resolve | Multiline editor, popup display; navigation in rendered Org |
| Collection | One review buffer can contain many files; commented hunks grouped with notes | Current buffer only; quoted spans and notes in Org |
| Delivery | Copy/show/save Markdown, JSON, Agent Shell and other adapters | Copy Org text or temporary export path; manual handoff |
| Persistence | Local sexp review store; auto-save defaults on | No annotation save/reload |
| Changed source | Numeric lookup; context retained for future recovery | Overlays follow ordinary edits; no snapshot recovery |
| Best fit | Review an agent's code changes in batches | Quick comments on text, including agent replies |

Sources: [hunk-notes data](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-core.el),
[range comments](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-comments.el),
[prompt generation](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-prompt.el),
[storage](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-storage.el),
[reviewer implementation](https://github.com/SreenivasVRao/reviewer.el/blob/eb69ed60897c8e5dc2a684025033f5423248b5ad/reviewer.el).

### Adoption gaps in hunk-notes

1. **Review coverage.** `hunk-notes-git-review-working-copy` uses plain `git diff`:
   staged and untracked changes are absent. Explicitly define the reviewed diff;
   do not interpret the command as all current changes. A revision or explicit
   diff buffer is a clearer first trial.
   [Git source](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-git.el)
2. **Stale locations.** The review key hashes repository/backend/revisions/diff ID,
   not diff contents. Loading reads the comment list without checking saved
   metadata against the new diff. Lookup uses file/side/line/change type; nearby
   context does not protect against a different line now occupying the old
   number. Treat a changed diff as a new snapshot until validated.
   [Key](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-core.el),
   [load](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-storage.el),
   [lookup](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-diff.el)
3. **Target session.** Its Agent Shell adapter inserts text with auto-submit off
   by default, but does not pass an explicit `shell-buffer`. Bill's multiple
   sessions need target selection. It also does not maintain sent/acknowledged
   state; resolved is a local boolean.
   [Adapter](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-agents.el)
4. **Magit compatibility.** Core hooks support Magit diff/revision buffers and
   preserve their major mode. The separate `hunk-notes-magit-review-current`
   adapter has different dispatch conditions. Difftastic is not a unified diff;
   its compatibility remains unverified. Start in a dedicated unified review
   buffer before enabling it across Bill's Magit workflow.
   [Core hooks](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes.el),
   [Magit adapter](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-magit.el)

Reviewer.el has a separate caution: Magit ranges are buffer line numbers,
not source lines, and the exported filename uses only the source basename.
Two sources with the same basename can overwrite the same temporary export.
Its status/thread fields are useful groundwork, but the inspected command
surface does not implement replies or a resolution workflow.
[Renderer and command implementation](https://github.com/SreenivasVRao/reviewer.el/blob/eb69ed60897c8e5dc2a684025033f5423248b5ad/reviewer.el)

## Oh-my-pi: local source inspection

Inspected Bill's checkout at
`~/Repositories/forks/oh-my-pi`, HEAD
`47281d527671fb104936752b03872d13d077de1d`. It had no tracked/untracked changes
and was 24 commits ahead / 8 behind its configured upstream. Findings describe
this checkout; they are not claims about current upstream or the installed binary. Links
point to upstream merge base `b07a1c146d`, where the cited files match this
checkout (line numbers in `interactive-mode.ts` adjusted).

### Code review: frozen diff with file or line notes

`ResolvedReviewTarget` holds one raw diff and its parsed snapshot. The overlay
and review prompt consume the same snapshot. A file has old/new paths, a path
occurrence number, raw diff and rows. A line note stores old/new line numbers,
hunk header and the exact raw diff line; a file note stores the path and note.
The occurrence number distinguishes repeated sections for the same path, useful
when staged and unstaged diffs both mention it.
[Target snapshot](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/review/target.ts#L6),
[types](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/tui/src/overlays/annotation-types.ts#L17)

The overlay holds notes and undo snapshots in memory. Completion returns either
`review` or `paste`. Review builds the reviewer prompt with human notes as focus;
paste inserts just the collected feedback into the composer. Its review template
asks the agent to independently verify operator notes. There is no resolved,
reply or per-note durable ID field in this annotation model, and no review-store
write was found in this command/overlay path.
[Completion](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/annotate/index.ts#L185),
[overlay](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/tui/src/overlays/annotation-overlay.ts#L175),
[prompt template](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/review/prompts/annotations.md#L1)

### Text: source provenance plus exact quotation

Sources include latest assistant response, selected session message/block, file
or literal text. Session sources carry entry ID and session ID internally.
Notes apply to the whole text or one logical line, with an exact quote and note.
Visual line wrapping does not change that logical anchor. All text feedback is
pasted; the command returns no prompt to submit automatically.
[Source acquisition](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/annotate/text-source.ts#L83),
[text types](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/tui/src/overlays/annotation-types.ts#L54),
[command](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/annotate/index.ts#L225)

Files/code/commands/literal text are included verbatim. The latest response is
called "your last reply" and only the selected lines are quoted. Older session
prose over 1,000 characters may be summarized, with exact quotes/notes retained
and full-source fallback on failure. The formatted text does not expose the
internal entry/session IDs or line numbers; it relies on label, quote and context.
For cross-session handoff, retain explicit provenance and the snapshot rather
than relying on "last reply".
[Formatter](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/annotate/text-review.ts#L6),
[template](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/extensibility/custom-commands/bundled/annotate/prompts/text-review.md#L1)

### Plan review: structure-aware anchors and a refine action

Plan notes target sections or rendered line context. Retained state includes
heading title, ancestry path, section content hash, index and optional line
context. Restoration matches path/title/hash and relocates line context; missing
matches are skipped. Duplicate section candidates choose the closest old index,
so this is stronger checking, not a guarantee against all ambiguity.
[Plan state and restoration](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/tui/src/overlays/plan-review-overlay.ts#L437)

InteractiveMode keeps this state in a process-memory map keyed by plan path.
Closing/reopening can retain it; this is not a persisted annotation database.
"Refine plan" sends collected feedback and clears retained notes on the
successful dispatch path. Approval/execution is a separate action. Section
deletion changes the plan file; annotation notes themselves form feedback.
[Owner state](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/modes/interactive-mode.ts#L1545),
[callbacks](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/modes/interactive-mode.ts#L6512),
[refine delivery](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/packages/coding-agent/src/modes/interactive-mode.ts#L6627)

**Agent Shell implication:** `/annotate` uses native interactive UI. Without it,
text annotation refuses to send; code-review annotation delegates to `/review`.
*Correction (round 4, [agent-apps survey](04-agent-apps.md)):
under ACP the UI checks pass but the overlay and paste calls are stubs, so
`/annotate` silently does nothing there.*
These TUI features do not automatically become annotation UI over ACP. Emacs
needs its own capture/collection frontend; it can reuse ordinary prompt delivery.
[Command behavior](https://github.com/can1357/oh-my-pi/blob/b07a1c146d0d12cfc855a2c65d52f892ef319040/docs/slash-command-internals.md#L427)

## Application survey

| Application | Model | Delivery | Useful idea for Emacs |
| --- | --- | --- | --- |
| tuicr | Saved review session; file/line/range/review comments | Prompt export or structured review CLI | Separate review identity, comments and reviewed-file progress |
| Crit | Persistent review with rounds, anchors, snapshots and replies | Finish Review collects feedback; experimental per-note send | Preserve quotes and expose drift after code changes |
| VS Code Agents window | Range feedback within a selected agent session | Add several notes, then Submit Feedback | Clear batch boundary and session ownership |
| Antigravity | Comments on plans/artifacts and code diffs | Review sends feedback; Proceed advances execution | Keep feedback and execution approval separate |
| Hunk | Live review with human notes and agent explanations/replies | Session CLI or agent-context sidecar | Bidirectional comments with explicit author and parent anchor |

### Tuicr: saved review sessions and portable feedback

Tuicr supports review/file/line/range comments, pending-comment summaries and
Markdown clipboard/stdout export. Its CLI lists saved sessions and reads comments
for agents. Session identity includes repository, base commit, diff source and
selected range. Comment records include ID, body, old/new side, optional line
range/context, author, commit identity and forge lifecycle state. File records
hold content hashes and reviewed-hunk keys; changing the hash invalidates review
progress. That does not prove all comments relocate correctly.
[Workflow](https://github.com/agavra/tuicr#to-your-coding-agent),
[CLI](https://github.com/agavra/tuicr/blob/00a738e2b12a9d9d9619482ce5c6e115dc1f1e65/docs/REVIEW_CLI.md),
[comments](https://github.com/agavra/tuicr/blob/00a738e2b12a9d9d9619482ce5c6e115dc1f1e65/src/model/comment.rs#L139),
[review state](https://github.com/agavra/tuicr/blob/00a738e2b12a9d9d9619482ce5c6e115dc1f1e65/src/model/review.rs#L33)

Transferable idea: make prompt export one view of stored review data. Keep
"sent", "posted to a forge", "file reviewed" and "issue resolved" distinct.

### Crit: persistent comments, review rounds and visible drift

Crit covers plans, files, Git diffs and live applications. Reviews are local;
ambiguous session selection requires an explicit session. Finish Review batches
feedback. Experimental Send now sends a note and source context to a subprocess
and records its output as a reply.
[Workflow and experimental send](https://github.com/tomasz-tomczyk/crit)

Its records include scope, range, old/new side, quote/offset, text anchor, drift,
author, round, replies, resolution and view identity. Historical file snapshots
live separately from comment JSON. Relocation uses line-sequence mapping and
anchor verification/search; duplicate matches choose the nearest predicted
position, and failed matches become drifted. Its Codex workflow asks agents to
reply with changes and leaves resolution to the human unless authorized.
[Comment model](https://github.com/tomasz-tomczyk/crit/blob/e48627e9602fcc704b6483890754d8a48cbdb2ef/internal/session/session.go#L129),
[snapshot storage](https://github.com/tomasz-tomczyk/crit/blob/e48627e9602fcc704b6483890754d8a48cbdb2ef/internal/session/round_snapshot.go#L5),
[anchor repair](https://github.com/tomasz-tomczyk/crit/blob/e48627e9602fcc704b6483890754d8a48cbdb2ef/internal/session/watch.go#L959),
[resolution ownership](https://github.com/tomasz-tomczyk/crit/blob/e48627e9602fcc704b6483890754d8a48cbdb2ef/integrations/codex/skills/crit/SKILL.md#L75)

Transferable idea: retain the original evidence and show when it no longer
matches. A reply can explain a fix without automatically resolving the note.

### VS Code and Antigravity: explicit submission boundaries

VS Code's native Agents window lets users add feedback to several code or
Markdown ranges, then submit the batch. Agents edit and resolve feedback;
resolved comments disappear. File-reviewed marks are separate and clear when
files change. The inspected public documentation does not establish an internal
snapshot schema or relocation guarantee.
[Official documentation](https://code.visualstudio.com/docs/agents/run/review-code-edits)

Antigravity makes implementation plans reviewable artifacts. Users comment,
submit through Review, or choose Proceed to advance execution. Code diffs also
support comments. The inspected docs do not specify persistence or anchor repair.
[Plan artifacts](https://www.antigravity.google/docs/implementation-plan),
[Code review](https://www.antigravity.google/docs/ide/review-changes-editor)

Transferable idea: several notes form one deliberate request. For plans, keep
requesting revisions separate from approving execution.

### Hunk: comments can flow in both directions

Hunk's live review registers with a local daemon. Agents inspect loaded diff
anchors and add explanatory notes targeting a file and exactly one hunk,
old-line or new-line anchor. Replies inherit the parent's anchor. Agents can list
human notes and batch-apply notes/replies. The CLI distinguishes human and agent
ownership; it cannot create/edit human notes, though cleanup can remove them.
Agent-context JSON sidecars provide another route for explanatory annotations.
Durable storage and stale-anchor recovery were not verified in this survey.
[Agent workflow guide](https://github.com/modem-dev/hunk/blob/main/docs/agent-workflows.md)

Transferable idea: use the same source attachment for the human's question and
the agent's answer, with explicit authorship and parent comment ID. Do not
confuse this application, Hunk, with the Emacs hunk-notes package.

## What to borrow for Emacs

The surveyed tools use three broad models:

1. **Temporary feedback batch:** freeze content, annotate, collect, paste. OMP
   text/diff review and reviewer.el are close to this model.
2. **Saved review:** comments belong to a particular diff/snapshot and carry
   progress or resolution. Hunk-notes and tuicr supply much of this.
3. **Shared review conversation:** agents read/reply to persistent comment IDs;
   rounds and source drift become explicit. Crit is the clearest reference.

For Bill, adopt the second model for code, with the first model's explicit draft
handoff. A richer shared store can wait until repeated review rounds or agent
replies inside annotations are an actual need.

Minimum useful data, expressed conceptually rather than as a new API:

```text
Review: id, repository/session, source kind, source snapshot/revision
Comment: id, source identity, scope, side/range, original quote/context, body
Optional lifecycle: author, parent id, sent batch, resolved, stale
```

Keep the stored anchor separate from display positions. A diff uses old/new
source ranges and hunk context; an agent reply uses session/interaction identity
and quoted text; a plan uses headings plus section content. Render those records
as Markdown or Org for Agent Shell. Marking a batch sent should not imply that
the human accepted the agent's changes.

The first practical evaluation should check hunk-notes against an explicit
unified diff, multiline/range comments, saved/reopened reviews, changed diff
contents and selection of the intended Agent Shell session. Check staged,
unstaged and untracked coverage separately. Prefer original quotes/full
commented hunks over generated summaries for code feedback. No installed runtime
behavior has been verified yet; this research supports choosing an evaluation
target, not declaring it ready for all of Bill's Magit/Difftastic cases.
