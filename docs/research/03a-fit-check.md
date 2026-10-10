# Annotation fit check: hunk-notes vs reviewer.el (2026-10-10)

Sources examined (read-only):

- hunk-notes: fresh clone at `ba37f3d` (2026-06-13, "Remove weird SPDX from org-mode file")
- reviewer.el: fresh clone at `eb69ed6` (2026-08-23, "Revise README.")
- agent-shell fork: `~/Repositories/forks/agent-shell` at `70616c4` (2026-10-10)
- magit: `~/.config/emacs/.local/straight/repos/magit/lisp` at `67f2038` (2026-08-01)
- magit-difftastic fork: `~/Repositories/forks/magit-difftastic` at `098d895`
- Doom config: `modules/home/emacs/doom.d/config.org`

Smoke scripts (batch `emacs -Q`, Emacs 31.1.50; the running server was not touched):
`smoke.el`, `hn.el`.

## Bottom line

Neither package covers the whole workflow (Magit + files + agent-shell transcript -> one batch -> agent-shell).

- **hunk-notes** works only with unified diffs. It handles stock `magit-diff`/`magit-revision` buffers with gaps. It cannot annotate plain files or agent-shell buffers. It has a working agent-shell sender.
- **reviewer.el** annotates any buffer with plain overlays. Each annotation is only a buffer position range. Annotations survive streaming output and collapse/expand in agent-shell. They are destroyed by any delete-and-reinsert, and every Magit refresh does that. It has no agent-shell sender and no way to combine annotations from several buffers. It has no license.

So reviewer.el is the closer starting point for "annotate anything", but it needs three things added: re-anchoring after refresh, a cross-buffer collector, and an agent-shell sender (about 10 lines, using `agent-shell-insert`).

---

## 1. hunk-notes in Magit

**Which buffers.**
- `hunk-notes--diff-like-mode-p` accepts `diff-mode`, `magit-diff-mode` and `magit-revision-mode` (`hunk-notes.el:76-79`).
- Auto-enable hooks exist only for `magit-diff-mode-hook` and `magit-revision-mode-hook` (`hunk-notes.el:382-384`), and only when `hunk-notes-auto-enable-in-diff-buffers` is non-nil (`hunk-notes.el:35`, `:365-368`).
- `magit-status-mode` derives from `magit-mode`, not `magit-diff-mode` (`magit-status.el:444`; compare `magit-diff.el:2381`, `magit-revision-mode` at `magit-diff.el:3020`). So:
  - Running `M-x hunk-notes-mode` in a status buffer reaches `(diff-mode)` (`hunk-notes.el:224-228`; same coercion in `hunk-notes-start` at `:245-248`). This **replaces the Magit status major mode with diff-mode**. Only the auto path passes `:preserve-major-mode t` (`hunk-notes.el:348`), and the auto path is not hooked for status.
  - The status-map binding `C-c R` -> `hunk-notes-magit-review-current` (`hunk-notes-magit.el:62-65`) checks `(derived-mode-p 'diff-mode)` (`:39`). That check is false in every Magit buffer. It then falls back to `magit-commit-at-point` (`magit-git.el:1750-1760`) and, if it finds a commit, opens a separate `git show` diff-mode buffer (`hunk-notes-git.el:64-72`). Otherwise it signals a user-error. It never annotates the status buffer in place.
  - Note that `hunk-notes-magit-review-current` also fails its first branch in `magit-diff-mode`, which is not derived from `diff-mode`. In a revision buffer it opens a *new* `git show` buffer instead of annotating the Magit buffer. In-place Magit annotation happens only through auto-enable (`hunk-notes--infer-auto-context`, `hunk-notes.el:328-336`).

**Point -> file/line mapping.**
- `hunk-notes-diff-position-info` (`hunk-notes-diff.el:125-234`) rescans the buffer **from `point-min`** on every call. It classifies each line by regexp (`hunk-notes-diff--line-kind`, `:75-88`) and recognizes:
  - `diff --git`
  - Magit/jj compact headings `^(modified|added|removed) +` (`:81`, `:119-123`)
  - `---`/`+++`
  - `@@ -a,b +c,d @@` (`hunk-notes-diff-parse-hunk-header`, `:26-54`)
- It then counts old/new lines through `+`/`-`/space lines.
- Rendering finds the position again with `hunk-notes-diff-find-position` (`:236-333`), keyed on `(file side line change-type)`. The first match wins.

**Problems against real Magit text.** Magit's default file heading is `(format "%-11s" status)` + file (`magit-format-file-default`, `magit-diff.el:2868-2872`). Magit's status values include `"new file"`, `"deleted"` and `"renamed"` (`magit-diff.el:2739-2794`).
- **New, deleted and renamed files are misattributed.** Those headings do not match `modified|added|removed`, so the parser keeps the *previous* file name. Verified in `hn.el`: a `+hello` line under `new file   b.el` reports `("a.el" new 1)`.
- **Staged and unstaged copies collide in the status buffer.** Nothing marks the section ("Unstaged changes" / "Staged changes"). If the same file/side/line appears in both, `find-position` renders the comment on the first one. Verified: a note for the staged `+new` line renders on the unstaged one (buffer line 5 instead of 15).
- **Untracked files** appear in status as bare file names with no hunks, so there is nothing to anchor to.
- **Collapsed status sections**: Magit washes file hunks eagerly and only hides them (`magit-diff-insert-file-section`, `magit-diff.el:2842-2863`, hidden in status at `:2846`), so the text is present. The parser could see it, but the status-mode coercion above blocks you first.
- **Magit refresh**: hunk-notes adds nothing to `magit-refresh-buffer-hook` (grep shows no `refresh` hook use outside its own `hunk-notes--maybe-refresh`, `hunk-notes-core.el:223`). After `g`, `erase-buffer` (`magit-mode.el:1139`) evaporates its overlays (they are created with `evaporate t`, `hunk-notes-overlays.el:171`). Comments stay in `hunk-notes-comments` and in storage, but they are invisible until you run `hunk-notes-render-comments` again. Adding `(add-hook 'magit-refresh-buffer-hook #'hunk-notes-render-comments nil t)` would fix this.
- **Default render style is risky in Magit.** `hunk-notes-render-style` defaults to `inline-text` (`hunk-notes-overlays.el:55`), which *inserts* read-only text blocks into the buffer (`:144-158`, `:185-198`). Inside Magit sections that text would be part of section bodies. Auto-enable switches to `overlay` (`hunk-notes.el:59`, `:372-374`); manual use does not.

**Bill's Magit rendering** (`config.org`):
- No `magit-delta` or delta pager. The only `magit-diff` customization is faces (`config.org:1713-1719`) and `--no-ext-diff` for stash (`:2504-2507`).
- `magit-difftastic-mode` is on (`config.org:2706-2721`) with `magit-difftastic-default-rendering 'stock` (`:2720`) and `magit-difftastic-status-buffers nil` (`:2716`). Files therefore start as **stock Magit unified hunks**, which hunk-notes can parse (with the gaps above).
- A file switched to difftastic with `C-c C-d` gets a `@@ line N @@` heading (`magit-difftastic.el:2156`) and side-by-side body lines with no `+`/`-` prefix (`magit-difftastic-display "side-by-side-show-both"`, `:166`). `hunk-notes-diff-parse-hunk-header` rejects that heading, and hunk state is cleared (`hunk-notes-diff.el:176-184`). As a result, **lines in difftastic-rendered files cannot be annotated**. Verified: `("  5 foo" -> (nil nil nil))`. This fails safely (no error), but those lines simply get no annotation.

## 2. hunk-notes outside diffs

- It cannot annotate plain files or agent-shell buffers. Every anchor comes from `hunk-notes-diff-position-info`. When there is no hunk it returns nil, and the comment commands signal "Region does not cover changed or context lines in a unified diff" (`hunk-notes-comments.el:150-151`).
- Enabling the mode in a non-diff buffer forces `(diff-mode)` (`hunk-notes.el:226-228`). That would destroy an agent-shell buffer's major mode.
- Making it work would require a second anchor model (buffer + file/line, or text-property-based), a second finder in place of `hunk-notes-diff-find-position`, and a different prompt builder. `hunk-notes-generate-prompt` (`hunk-notes-prompt.el:219-277`) is diff-shaped. That is a rewrite of the core rather than an adapter.
- The prompt also covers **one buffer only**: it reads buffer-local `hunk-notes-comments` (`hunk-notes-prompt.el:224`). There is no cross-buffer collection.
- Its useful part is the sender: `hunk-notes-send-to-agent-shell` calls `(agent-shell-insert :text … :submit hunk-notes-auto-submit-to-agent)` (`hunk-notes-agents.el:120-128`). It passes no `:shell-buffer`, so the shell comes from project resolution (see section 5).

## 3. reviewer.el on agent-shell buffers

**reviewer's model.** Each annotation is one `make-overlay start end` with default advance flags, `face` and `evaporate t`. The data lives in overlay properties (`reviewer.el:127-136`). There is no persistence and no re-anchoring (commentary at `:17-26`). `reviewer-all-annotations` reads the overlays live (`:53-56`).

**What agent-shell does to its own text.**
- Streaming appends: `agent-shell-ui-update-fragment` with `:append` -> `agent-shell-ui--append-body` inserts at the body end (`agent-shell-ui.el:501-551`). New blocks go at `point-max` (`:396-402`).
- Collapse/expand: `agent-shell-ui--toggle-leaf-fragment-at-point` (`agent-shell-ui.el:1337-1391`) only `put-text-property 'invisible` on the body (`:1367-1369`). It deletes and reinserts only the 2-char indicator `▶ `/`▼ ` (`:1371-1374`). Groups use `agent-shell-ui--set-group-collapsed` (`:1048-1060`), which also only sets properties. Expanding runs `agent-shell-ui-post-expand-fragment-at-point-hook` (`:1391`), which agent-shell binds to `agent-shell--render-markdown-body` (`agent-shell.el:7117-7118`, defined `:453-465`). That markdown render deletes delimiter characters (`agent-shell-markdown.el:610-611`) but keeps the content characters.
- Body replacement: a non-append update goes to `agent-shell-ui--replace-body`, which runs `delete-region body-start body-end` and reinserts (`agent-shell-ui.el:553-589`, delete at `:568`). **Every tool-call update uses this path**: `agent-shell--render-tool-call-fragment` passes `:body` with no `:append` (`agent-shell.el:3854-3888`, body at `:3880-3884`), and it is called again for each `tool_call_update` (`agent-shell.el:4438ff`). The wrapper `agent-shell--update-fragment` (`agent-shell.el:7421ff`) forwards `:body`/`:append` unchanged to `agent-shell-ui-update-fragment` (around `:7550-7562`). It has no equality check, so even an unchanged body is deleted and reinserted.
- Label rewrite: `agent-shell-ui--replace-label` deletes and reinserts the label (`agent-shell-ui.el:622-673`, delete at `:658`). It skips the rewrite if the rendered text is unchanged (`:646-654`).
- Full block regeneration: when a body arrives for the first time on a labels-only block, `update-fragment` deletes the block and reinserts it (`agent-shell-ui.el:344-347`). `agent-shell-ui-delete-fragment` removes blocks (`:675-705`).
- Tables and images: on window resize, `agent-shell--realign-rendered` (`agent-shell.el:14631-14638`) -> `agent-shell-markdown--render-table` runs `delete-region table-start table-end` and reinserts (`agent-shell-markdown.el:3265-3267`).
- Viewport buffers are rebuilt with `erase-buffer` (`agent-shell-viewport.el:651`, `:2101`). Annotations placed in a viewport buffer would not survive paging or recompose.

**Verdict, confirmed with the real `agent-shell-ui` functions in `smoke.el`:**

| Event | reviewer overlay |
|---|---|
| (i) new blocks / output streamed below | survives |
| (i') append into the *same* block body after the annotated text | survives (rear-advance nil, so it does not grow) |
| (ii) collapse, then expand (leaf fragment) | survives; text only gets `invisible` |
| markdown delimiter strip on expand (`**bold**`) | survives, shrinks to `bold` |
| (iii-a) same label re-sent | survives (rewrite skipped) |
| (iii-b) body replaced, even with identical text (tool_call_update path) | **destroyed** (evaporates) |
| (iii-c) label text changes | **destroyed** for an overlay on the rewritten label section only. Status is `label-left` and title is `label-right` (`agent-shell.el:3876-3877`), and `--replace-label` rewrites one section at a time, so a title annotation survives a status-only change such as pending -> completed |
| table re-render on resize | **destroyed** |
| viewport buffer paging | **destroyed** (`erase-buffer`) |

In practice: annotations on settled agent-message prose survive. Annotations on a tool call that is still running, on its status/title label, or on a rendered table are lost **silently**: `evaporate` deletes the overlay and nothing records the loss. Two more gaps for transcripts:
- `reviewer--line-range` reports buffer line numbers (`reviewer.el:324-330`).
- `reviewer--buffer-label` falls back to the buffer name (`:355-367`).

The quoted span is the only useful anchor for the agent.

## 4. reviewer.el in Magit

- `magit-refresh-buffer` (`magit-mode.el:1095-1132`) calls the refresh function wrapped by `magit--refresh-buffer-function`, which does `(erase-buffer)` (`magit-mode.el:1133-1140`, erase at `:1139`).
- `erase-buffer` collapses every overlay to zero length at `point-min`. With `evaporate t`, they are deleted. Verified: after an erase and reinsert, `reviewer-all-annotations` returns 0.
- Every `g`, stage, unstage, commit, or auto-refresh after a file save wipes all reviewer annotations in that Magit buffer. reviewer has no hook into `magit-refresh-buffer-hook` (`magit-mode.el:305`) and stores nothing outside the overlay.
- Otherwise its Magit support is shallow:
  - `reviewer--magit-file-at` uses `magit-file-at-point` (`reviewer.el:345-348`), which is good.
  - Commit and branch come from `magit-buffer-revision(-hash)` / `magit-get-current-branch` (`:332-343`).
  - Line numbers are **buffer** lines (`:324-330`), not file lines.
  - The src-block lang is forced to "diff" (`:320-322`).

## 5. agent-shell delivery API (fork)

- `agent-shell-insert (&key text submit no-focus shell-buffer)` (`agent-shell.el:12983-13007`):
  - If the caller is not in `agent-shell-mode` and viewport interaction is preferred, or the caller is a viewport buffer, it appends to the viewport compose buffer via `agent-shell-viewport--show-buffer`.
  - Otherwise it calls `agent-shell--insert-to-shell-buffer`.
  - It returns `((:buffer . B) (:start . S) (:end . E))` or nil.
- `agent-shell--insert-to-shell-buffer` (`agent-shell.el:12915-12981`):
  - The shell is `shell-buffer`, or `(agent-shell--shell-buffer :no-create t)` (`:12932-12933`).
  - It inserts at `point-max`, prefixed by `"\n\n"` unless submitting (`:12957-12960`), then calls `shell-maker-submit` when `submit` is set (`:12965-12966`).
  - `no-focus` skips `agent-shell--display-buffer` (`:12945-12949`).
  - If the shell is busy and either `submit` is set or no live prompt exists, it signals `"Busy, try later"` (`:12951-12953`).
  - If the session is not ready, it subscribes to `prompt-ready` and retries (`:12970-12980`).
- Busy-safe pattern used by the fork's own senders (`agent-shell-send-region`, `agent-shell.el:13009-13025`): check `agent-shell--can-insert-into-prompt-p` (`agent-shell-prompt.el:172-189`). If it fails, queue with `agent-shell--prompt-send :prompt (agent-shell--prompt-queue-read :initial …)`.
- Picking a shell:
  - `agent-shell--shell-buffer (&key viewport-buffer no-error no-create)` (`agent-shell.el:11633-11686`). Resolution order: viewport -> current agent-shell buffer -> first shell in the same project (`agent-shell-project-buffers`, `:11624-11631`) -> prompt to create one.
  - `agent-shell--read-shell-buffer (&key prompt buffers force-short-names)` (`agent-shell.el:2140ff`) is a `completing-read` over shells with icon, status and title columns. It is used by `agent-shell-send-region` with a pick-shell prefix (`:13015-13017`).
  - `agent-shell-buffers` (`agent-shell.el:2054-2069`) lists all shells, most recent first.
- Caveat for hunk-notes' sender: it passes no `:shell-buffer`, so from a Magit buffer the project resolution picks the first shell in that repo, or signals a user-error if none exists. Busy shells hit "Busy, try later" when `submit` is set.

## 6. Size, quality, license

| | hunk-notes | reviewer.el |
|---|---|---|
| Elisp lines | 2,643 in 12 files (core 235, diff 340, comments 512, overlays 244, prompt 319, agents 221, storage 95, magit 68, git 84, jj 87, vc 51, main 387) | 551, one file |
| Tests | `tests/hunk-notes-tests.el`, 344 lines, 21 ERT tests; **21/21 pass** in batch. No Magit test. | none |
| Package-Requires | `((emacs "27.1"))`; `transient` and `magit` are soft (`require … nil t`) | `((emacs "29.1") (transient "0.4.0"))`; hard `(require 'org)`; optional posframe |
| License | GPL-3.0-or-later (LICENSE + SPDX headers) | **no LICENSE file and no license header** (all rights reserved by default) |
| History | 6 commits, all on 2026-06-13; no activity since | 37 commits, 2026-08-14 to 2026-08-23 |
| Persistence | yes, `~/.emacs.d/hunk-notes/reviews/<sha1>.el` (`hunk-notes-storage.el:14-18`) | none, session-local overlays (`reviewer.el:17`) |
| Agent handoff | copy/buffer/shell/agent-shell/eca/gptel/pi/ai-code (`hunk-notes-agents.el:197-218`) | render to org, copy, or write the path of `/tmp/reviewer-<base>.org` (`reviewer.el:400-482`); no sender |
| Multi-buffer collection | no (buffer-local) | no (buffer-local; `*reviewer:<name>*` per buffer) |

## What the workflow would actually need

1. **An anchor that survives re-render.** Store the annotation as data rather than as an overlay alone: buffer kind, file, file line (for Magit, the side and line from `magit-diff-visit--position`-style logic or hunk-notes' parser), the quoted text, and a few lines of context. Re-find it after `magit-refresh-buffer-hook` and after agent-shell updates by text search. A tool-call label rewrite also changes the text, so anchor transcript notes to the fragment's `agent-shell-ui-state :qualified-id` plus the quoted text.
2. **A global collector** across buffers, not a per-buffer list.
3. **A sender**: `agent-shell--read-shell-buffer` to pick a shell, then `agent-shell-insert :text … :shell-buffer …`, with the `--can-insert-into-prompt-p` / queue fallback.

reviewer.el is small enough to fork or wrap for this, but its missing license is a blocker for vendoring. hunk-notes' diff parser could be reused for the Magit side once two things are fixed: the `new file`/`deleted`/`renamed` headings, and per-section staged/unstaged scoping.

## Not verified

- Live behavior in Bill's running Doom (evil keymaps, `C-c r`/`C-c ,` conflicts, magit-section highlight overlays covering reviewer's face). Nothing was loaded into the server.
- Group-level collapse with a reviewer overlay inside a group child. This was checked from source only (`agent-shell-ui.el:1048-1060`, property-only), not in the smoke test.
- `hunk-notes-git` buffers and jj buffers were not exercised beyond the package's own tests.
