# Emacs annotations collected as agent feedback

Researched 2026-10-10 against upstream documentation and source. This is a
comparison and proposed workflow, not an installed or runtime-tested integration.

## Recommendation

For Bill's code-review workflow, prefer **emacs-hunk-notes**. The
[closer comparison and application survey](02-annotation-models.md)
examines its remaining gaps and the annotation model in Bill's local oh-my-pi.

Use **reviewer.el** if the main task is selecting
passages in code, prose, or agent responses and writing several comments before
handing them back. It already collects the current buffer's annotations into
readable Org containing quoted text and notes. Its main limitation is that the
annotations disappear when their buffer dies. [Project documentation](https://github.com/SreenivasVRao/reviewer.el)

If most feedback is on **code changes**, evaluate **emacs-hunk-notes** first:
it records diff locations, saves reviews, produces Markdown prompts and already
has an Agent Shell adapter. The project describes itself as an early
implementation; those features have been checked in source, not exercised in
Bill's Doom environment. [Project documentation](https://github.com/ArthurHeymans/emacs-hunk-notes)

For **persistent reading notes**, choose **org-remark**. For a simpler persistent
file-review system with existing annotated-diff export, consider **annotate.el**.
Neither supplies a verified Agent Shell transcript integration.
[Org-remark](https://github.com/nobiot/org-remark),
[annotate.el](https://github.com/bastibe/annotate.el)

## Comparison

| Package | Best use | Collecting feedback | Main constraint |
| --- | --- | --- | --- |
| [reviewer.el](https://github.com/SreenivasVRao/reviewer.el) | Temporary comments on arbitrary text buffers, files and Magit diffs | Per-buffer Org render; copy text or exported path | No annotation save/reload; no project-wide collector |
| [emacs-hunk-notes](https://github.com/ArthurHeymans/emacs-hunk-notes) | Human review of unified diffs | Markdown prompt, JSON export, Agent Shell adapter | Diff-specific; early implementation |
| [annotate.el](https://github.com/bastibe/annotate.el) | Persistent annotations on files | `annotate-export-annotations` creates an annotated unified diff | Transient buffers lack a useful durable identity |
| [org-remark](https://github.com/nobiot/org-remark) | Highlights and long-lived reading notes | Ordinary Org marginal-notes file | Batch delivery and unsupported-mode integration need glue |
| [simply-annotate](https://github.com/captainflasmr/simply-annotate) | Threaded feedback with status, priority and tags | Org export for buffer/project/all | Export omits source range and selected quote |
| [annot](https://github.com/ghoshi/annot) | Text/image annotations on files | No batch exporter found in inspected commands | Non-file annotations are not persisted |
| [org-noter](https://github.com/org-noter/org-noter) / [PDF Tools](https://github.com/vedang/pdf-tools) | PDFs and document review | Org notes / PDF annotation API | Document-specific collection |
| [agent-review](https://github.com/nineluj/agent-review) | Agent-generated review findings | Mark findings and send a selected batch | Generates findings rather than serving as a human annotation editor |

## What Agent Shell already provides

Agent Shell supplies transport and composition: `agent-shell-insert` accepts
text and a target shell, with optional submission. `agent-shell-send-region-to`
lets the user choose a session. Its current implementation inserts region context
into a draft when possible; otherwise it opens the queue prompt flow. The name
"send" should not be read as unconditional immediate submission.
[Source: insertion and region commands](https://github.com/xenodium/agent-shell/blob/99b9922285f5c5c5b38e5e4a0016cb9ef3c16ef7/agent-shell.el)

The inspected source also has region quotation and response quotation. These
are useful for immediate feedback but do not supply a multi-comment annotation
store or collector. A general collector can produce text and use the existing
composition route; implementing a new ACP transport is unnecessary.
[Command documentation](https://github.com/xenodium/agent-shell/blob/99b9922285f5c5c5b38e5e4a0016cb9ef3c16ef7/README.org)

The repository already customizes Agent Shell context sources for Magit, binds
region/prompt commands under `SPC k`, and configures org-noter for DocView. These
are configuration observations, not proof of the interactive server's loaded
state. No reviewer, hunk-notes, org-remark or simply-annotate configuration was
found in the inspected `config.org`.
Source: Bill's private Doom config (`config.org`), not public.

## Closest matches and source caveats

### reviewer.el: smallest general starting point

`reviewer-annotate` works on a region or word, opening a note-editing buffer.
`reviewer-render` exports all annotations in the current buffer to an Org file
under `/tmp/`. `reviewer-yank-render` copies the text; the file-name variant copies
the export path. It leaves source text untouched and supports non-file buffers.
[README](https://github.com/SreenivasVRao/reviewer.el/blob/eb69ed60897c8e5dc2a684025033f5423248b5ad/README.org)

The annotations are overlays, with no save/reload mechanism. Export is a snapshot,
not restoration. For Magit it adds repository/branch/HEAD and per-entry file
metadata, but `reviewer--line-range` uses `line-number-at-pos`: the range describes
the **display buffer**, not the underlying old/new file. Preserve the quoted diff
and verify locations before agents act on those numbers. Collection is per
buffer, so combining several files requires manual merging or a small adapter.
[Renderer and line-range source](https://github.com/SreenivasVRao/reviewer.el/blob/eb69ed60897c8e5dc2a684025033f5423248b5ad/reviewer.el)

### emacs-hunk-notes: strongest existing diff loop

The package supports comments on selected line ranges, editing, resolution,
navigation, saved local reviews and JSON export. Prompt generation includes
repository/revision metadata, comment IDs, old/new line ranges and commented
hunks by default. Resolved comments are still included and labelled resolved;
the instructions ask the agent to address unresolved comments.
[Storage source](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-storage.el),
[Prompt source](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-prompt.el)

`hunk-notes-send-to-agent-shell` calls `agent-shell-insert`; automatic submission
defaults to nil. It does not pass an explicit target shell, so a multi-session
workflow should verify the chosen session or add target selection. Magit entry
points exist, but compatibility with Bill's Difftastic display is unverified:
the core expects unified diffs, so use its dedicated review buffer initially.
[Adapter source](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-agents.el),
[Scope and entry points](https://github.com/ArthurHeymans/emacs-hunk-notes)

Its Git working-copy entry point runs plain `git diff --no-ext-diff --`, which
omits staged and untracked changes. Saved reviews are keyed by repository,
backend, revisions and diff identifier, without a diff-content hash. Nearby
context is stored for future recovery, not used for robust relocation today.
[Git entry points](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-git.el),
[Review keys](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-core.el),
[Position lookup](https://github.com/ArthurHeymans/emacs-hunk-notes/blob/ba37f3d70927c028e5c15a0982cacac99279434d/hunk-notes-diff.el)

### Persistent alternatives

**annotate.el** stores annotations separately, supports replies and exports
annotated unified diffs. Use `annotate-export-annotations`; the separate
`annotate-integrate-annotations` command writes comments into source. Restoration
searches near displaced text and warns on failure. Its identity function falls
back to an empty string for unsupported buffers, so arbitrary agent buffers
need a different persistence design.
[README](https://github.com/bastibe/annotate.el),
[identity, restoration and export source](https://github.com/bastibe/annotate.el/blob/master/annotate.el)

**org-remark** keeps highlights and notes in ordinary Org, with integrations for
files, EWW, Info and nov.el. It stores source links, selected-text headings and
positions, and adjusts mismatched positions using nearby text. Agent Shell
support would need a mode-specific source identity/link integration. Org storage
is convenient for collecting selected notes, but delivery state is custom work.
[README](https://github.com/nobiot/org-remark),
[persistence and adjustment source](https://github.com/nobiot/org-remark/blob/main/org-remark.el)

**simply-annotate** provides richer review state and buffer/project/all Org
export. Source supports custom identity functions and nearby text relocation
with stale marking. However, `simply-annotate--thread-to-org` exports thread data
and file identity without the range or selected quote. An agent-ready collector
must add those. Buffer-name identity also needs replacement for durable session
annotations. Its README comparison table contradicts the other packages' own
documentation about replies and Info support; this comparison uses their sources.
[README](https://github.com/captainflasmr/simply-annotate),
[identity, relocation and export source](https://github.com/captainflasmr/simply-annotate/blob/main/simply-annotate.el)

**annot** requires a file buffer to save annotations; no batch exporter was
found. **org-noter** stores external Org notes synchronized to document positions.
**PDF Tools** exposes `pdf-annot-getannots` for collection, but a useful prompt
needs page numbers, note contents and quotations; saving PDF annotations changes
the PDF. These are secondary choices for this task.
[annot source](https://github.com/ghoshi/annot/blob/master/src/annot.el),
[Org-noter documentation](https://github.com/org-noter/org-noter),
[PDF annotation source](https://github.com/vedang/pdf-tools/blob/master/lisp/pdf-annot.el)

## Proposed workflow

1. Select text and add notes while reviewing. Keep source text unchanged.
2. Collect notes into one readable feedback draft, preserving quotations and
   source identity. Use existing Org or Markdown output first.
3. Choose the intended Agent Shell session, inspect/edit the draft, then submit.
4. Keep the exported batch until the response has been checked; clear or resolve
   notes only through an explicit action.

For reviewer.el this can be done manually today: `reviewer-render`, select the
rendered text, then `agent-shell-send-region-to` and review the resulting prompt.
For hunk-notes: open a unified diff review, annotate, inspect
`hunk-notes-show-prompt`, then use its Agent Shell adapter with auto-submit off.
These sequences are inferred from the verified commands; no end-to-end run was
performed.

For annotating **agent responses**, use a saved transcript or a stable response
snapshot first. Agent Shell's viewport initializer erases and repopulates its
buffer; therefore, ordinary positional overlays cannot be assumed to survive
navigation or refresh. A future durable integration should store session ID,
interaction identity, original quote and note separately from the display.
[Viewport source](https://github.com/xenodium/agent-shell/blob/99b9922285f5c5c5b38e5e4a0016cb9ef3c16ef7/agent-shell-viewport.el)

A future cross-buffer adapter should preserve file/session identity, revision or
snapshot, quote, location, note and stable entry ID. Preview and target selection
matter more initially than automatic agent polling or an MCP server. This is a
design recommendation, not an existing feature claim.

## Verification before adopting

Research checked upstream READMEs and the implementation of collection, storage
and Agent Shell insertion. No packages were installed and no configuration was
changed. Before adopting, verify in a disposable Doom daemon: multiline notes,
read-only buffers, source edits/deletion, diff refresh, multi-file collection,
session selection and draft behavior while the agent is busy. Assert exported
payloads contain the actual quote, note and correct source location. Persistent
options also need save/reopen and stale-anchor checks.
