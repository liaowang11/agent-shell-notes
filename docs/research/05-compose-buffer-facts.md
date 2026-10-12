# Can agent-shell's compose buffer hold a review? (2026-10-11)

Answers [Can agent-shell's compose buffer hold a review?](../wayfinder/tickets/001-compose-buffer-facts.md).
Facts only; the choice is ticket 002.

Sources (read-only; HEAD read from `.git/refs/heads/main`, since `git -C` on
other repos was refused in this sandbox):

- agent-shell (Bill's fork) at `70616c4a4907ffba583c6dc7eb176b852e685a11`
- [agent-shell-side](https://github.com/liaowang11/agent-shell-side) at `68a950fb7b37560452657a9565b1bdb21c83c186`
- Bill's private Doom config (`config.org`)
- shell-maker (Bill's fork, one lookup in `shell-maker.el`)
- [agent-shell-vertico](https://github.com/liaowang11/agent-shell-vertico) at `f8995d959b54795b1e4e5478c2283d39e5bef6db` (one lookup)

Citations without a file name are in the agent-shell fork. `viewport.el` means
`agent-shell-viewport.el`.

**Read vs run.** Claims marked *(run)* were checked in a batch `emacs -Q`
(Emacs 31.1.50, straight build deps) with a throwaway script. The script
uses a fake shell buffer that is not in `agent-shell-mode`, with
`agent-shell-viewport--update-header` and `--position` stubbed and
`--busy-p` / `agent-shell--context` overridden per case. Everything else was
read from source. The running Emacs server was not touched.

## Bottom line

- Each shell has exactly one compose surface in viewport style: the buffer
  `<shell name> [viewport]`. It is the same buffer as the history viewer. It
  switches between `agent-shell-viewport-edit-mode` (compose) and
  `agent-shell-viewport-view-mode` (read a turn). The pairing is by buffer
  name only.
- A draft survives streaming, turn end and paging. It is lost when the
  viewport buffer is killed, when the shell is killed or restarted, on any
  send (the buffer is cleared), and on a few internal paths that switch to
  view mode without saving it first (one of them confirmed by a run).
- No caller can append to it without moving focus: `:no-focus` and `:submit`
  signal "Not yet supported", and every append selects the viewport window.
  Every append also resets the draft's busy-send disposition.
- Bill's config sets `agent-shell-prefer-viewport-interaction` to `t`, so
  `agent-shell-insert`, `send-region`, `send-dwim`, `prompt-compose` and
  queue edit all land in this one buffer. A review kept there would share it
  with everything else Bill composes for that session.
- The edit buffer is `text-mode`, not Markdown, and has no file or
  persistence.

## 1. One compose buffer per session: create, find, kill

**Viewport compose buffer.**

- Name: shell buffer name + `" [viewport]"` (`viewport.el:1102-1103`).
- Create/find: `agent-shell-viewport--buffer (&key shell-buffer existing-only)`
  returns the buffer with that name, or creates it in edit mode
  (`viewport.el:1105-1121`). *(run: exp 1)*
- Find the shell from the viewport: strip the suffix from the name
  (`viewport.el:2040-2050`). `agent-shell--shell-buffer` tries this first
  (`agent-shell.el:11633-11652`).
- One buffer, two modes. Edit mode is the draft. View mode shows one
  turn, read-only (`viewport.el:2080-2124`). Both are derived from
  `text-mode`.
- Calling `agent-shell-viewport-edit-mode` always erases the buffer
  (`viewport.el:2100-2101`). *(run: exp 2, a draft became `""`)*
- Kill:
  - Killing the shell kills the viewport (`agent-shell--clean-up`,
    `agent-shell.el:5493-5497`).
  - Killing the viewport from its own selected window asks "Kill shell
    session too?" (`viewport.el:2052-2078`).
  - Send paths kill it by default, or keep it, depending on settings
    (section 3).
- Rename: the link is the name. After a plain rename of the shell, neither
  side finds the other. *(run: exp 7, both lookups returned nil)*
  `shell-maker-set-buffer-name` also just calls `rename-buffer`
  (`shell-maker.el:2051-2057`). agent-shell-side renames the viewport by
  hand next to the shell for this reason (`agent-shell-side.el:840-868`).
- Restart/reload: `agent-shell-restart` kills the shell, so it also kills the
  viewport and its draft. It then starts a new shell under the old name and
  opens a new, empty viewport (`agent-shell.el:1739-1762`).
- The stable session key is `(:session :id)` in `agent-shell--state`
  (`viewport.el:289-292`), not the buffer name.

**Shell prompt region.** The shell's own input area after the live prompt.
`agent-shell--input` reads it (`agent-shell.el:11998-12014`), and
`agent-shell--prompt-input` / `--clear-prompt-input` read and clear it
(`agent-shell-prompt.el:191-222`). It dies with the shell.

**agent-shell-side.** It has no compose buffer of its own. It reuses the
viewport compose buffer of the target shell:

- `agent-shell-side-compat-compose-in-viewport` calls `--show-buffer :append
  text :edit t :disposition <existing>` (`agent-shell-side-compat.el:238-255`).
- Used for quoting a region (`agent-shell-side.el:1264-1281`) and for handing
  findings back (`agent-shell-side.el:1322-1347`).
- It checks for a draft as "edit mode and non-empty"
  (`agent-shell-side-compat.el:159-170`) or "snapshot held"
  (`:172-189`). It avoids paths that would wipe it
  (`agent-shell-side.el:1041-1073`, `agent-shell-side-compat.el:257-292`).

## 2. Does a draft survive?

| Event | Draft survives? | Evidence |
|---|---|---|
| Shell busy, caller appends text | Yes, stays in edit mode and appends | `viewport.el:237-243`; *(run: exp 5)* |
| Shell busy, caller shows viewport with no text and no `:edit` | **No.** Buffer switches to view mode with no snapshot. The next idle show erases it | `viewport.el:226-230`, `:244-258`; *(run: exp 4: view mode, snapshot nil, then `""`)* |
| Same, with `:edit t` | Yes | `viewport.el:226`; *(run: exp 5c)* |
| Turn streams / finishes | Yes. Every mirror into the viewport requires view mode (some also require the latest page) | `agent-shell.el:7268-7276`, `:7292-7299`, `:7504-7510`, `:7680-7686`, `:11500-11510` |
| First prompt on a shell with no ACP client yet | **No.** An existing viewport is switched to view mode and re-initialized, with no edit-mode check | `agent-shell.el:2898-2905` |
| Paging to history (`C-c C-p`) and back (reply) | Yes, via `--compose-snapshot` (permanent-local) | `viewport.el:115-119`, `:878-911`, `:1123-1150`; *(run: exp 5f/5g)* |
| `view-last` | Yes, parked in the snapshot if non-empty | `viewport.el:918-939` |
| `M-p`/`M-n` history | Yes, snapshotted, restored past the newest entry | `viewport.el:801-861` |
| Window dismissed (`quit-restore-window`) | Yes, the buffer is kept | `viewport.el:559-567` |
| `agent-shell-other-buffer` from the shell | Yes, a non-empty edit buffer is not switched | `agent-shell.el:2119-2127` |
| `agent-shell-prompt-queue-edit` (with prefer-viewport) | **No.** It erases the buffer to prefill the queued prompt, without asking | `agent-shell-prompt-queue.el:905-908`, `viewport.el:689-707` |
| `--show-buffer :override` (e.g. `prompt-compose` moving shell input) | Asks "Compose buffer is not empty. Override?" | `viewport.el:205-217` |
| Cancel (`C-c C-k`) | Asks "Discard composed prompt?" if non-empty | `viewport.el:762-799` |
| Viewport buffer killed | **No.** The snapshot is buffer-local | *(run: exp 6)* |
| Shell killed / restarted / reloaded | **No** | section 1 |
| Emacs restart | **No.** No file, no desktop/auto-save hook in `viewport.el` | grep of `viewport.el` |

Shell prompt region (no viewport): with `agent-shell-persistent-prompt-enabled`
(default `t`, `agent-shell-prompt.el:45-62`) the prompt stays during a turn,
and output lands above it (`agent-shell-prompt.el:120-161`). When the queue
drains, typed input is set aside and put back after the queued prompt is
submitted (`agent-shell-prompt-queue.el:128-143`).

## 3. Submit, queue, steer, and appending without focus

**Edit-mode keys** (`viewport.el:1632-1654`): `C-c C-c` send, `M-RET` send
by the override route, `C-c C-i` steer, `C-c C-q` queue, `C-c C-k` cancel,
`C-c C-p` previous page.

**What send does** (`agent-shell-viewport-compose-send`, `viewport.el:279-307`):

- If the draft's disposition is `steer`, it steers (`:296-297`).
- Otherwise: with a prefix arg it delivers and keeps an empty edit buffer.
  If `agent-shell-viewport-dismiss-on-send` is set, it delivers then
  dismisses. If `prefer-viewport-interaction` is set, it uses
  `send-and-wait-for-response`. Otherwise it uses `send-and-kill`.
- With Bill's settings the default is `send-and-wait-for-response`
  (`viewport.el:569-625`). The buffer becomes the view of the new turn (or
  is cleared, then `view-last`, when busy). The draft text is gone from the
  buffer either way.
- Exception in Bill's config: `+agent-shell-compose` and the
  `agent-shell-prompt-compose` advice set `dismiss-on-send` for the pending
  viewport (`config.org:5300-5346`). Sends from that pop-up go through
  `--compose-deliver` and then dismiss. The buffer is cleared and kept in
  edit mode (`viewport.el:370-396`, `:547-557`). Upstream's own
  `setq-local` in `prompt-compose` (`agent-shell.el:1947-1951`) is wiped by
  the mode switch `--show-buffer` does next. Bill's re-arm hook exists to fix
  that (`config.org:5277-5285`). A package that calls `--show-buffer`
  itself does not get this arming, so its draft takes agent-shell's
  default route.
- Every path sends `(string-trim (buffer-string))`, the whole buffer
  (`viewport.el:347`, `:386`, `:447`, `:499`, `:580`). There is no partial
  or region send.
- Before a session id exists, send signals "Starting agent, please wait"
  (`viewport.el:289-292`).

**Busy routing** (`agent-shell--prompt-send`, `agent-shell-prompt-queue.el:450-483`):

- `steer` steers or errors. `queue` enqueues. nil goes to
  `agent-shell-busy-submit-default-function`, which defaults to steer
  (`agent-shell-prompt-queue.el:556-577`).
- The default steer falls back to queue when the agent can't or won't steer
  (`:603-624`, `:424-448`).
- Queued prompts are merged into one turn when `agent-shell-prompt-queue-merge`
  is `t` (default) (`:87-95`, `:97-143`).
- `agent-shell--prompt-send` is callable from any code with a shell buffer
  current. Sending text needs no compose buffer at all.

**Appending from another buffer:**

- `agent-shell-insert` picks its target from the *current* buffer's mode
  (`agent-shell.el:12983-13010`). From a Magit or file buffer with
  prefer-viewport `t`, it calls `agent-shell-viewport--show-buffer`.
- `--show-buffer` signals `"Not yet supported"` for `:submit` and
  `:no-focus` (`viewport.el:191-194`). *(run: exp 3d/3e)*
- It always calls `agent-shell--display-buffer` (`viewport.el:204`), which
  selects the window (`agent-shell.el:8824-8829`). *(run: exp 3c, the
  selected window showed the viewport)*
- Text is appended at the end after `"\n\n"`. The return value is
  `((:buffer . B) (:start . S) (:end . E))`
  (`viewport.el:237-243`, `:263-265`). *(run: exp 3/3b)*
- With no `:append`, it pulls in `agent-shell--context` (region or line at
  point) (`viewport.el:199`). agent-shell-side passes `:append ""` to avoid
  that (`agent-shell-side-compat.el:207-220`).
- Every call overwrites `agent-shell-viewport--compose-disposition`, nil
  included (`viewport.el:259-262`). *(run: exp 5e, `queue` became nil)*
  agent-shell-side reads it first and passes it back
  (`agent-shell-side-compat.el:222-236`).
- Writing into the buffer directly with `with-current-buffer` + `insert`
  (no display) is not an API. Inside agent-shell, only the viewport's own
  commands do it (`--enter-compose-page`, `viewport.el:1138-1147`;
  `previous-history`, `:819-833`) and `--prefill-edit` (`:689-707`). Bill's
  config reaches the buffer through `agent-shell-viewport--buffer` only to
  set a buffer-local variable (`config.org:5304-5315`).
- Without the viewport, `agent-shell--insert-to-shell-buffer :no-focus t`
  inserts at the shell's `point-max` without displaying
  (`agent-shell.el:12915-12981`). It signals "Busy, try later" when busy with
  no live prompt (`:12951-12953`). agent-shell-side uses it directly for this
  reason (`agent-shell-side-compat.el:294-308`).

## 4. A shell without the viewport

- `agent-shell-prompt-compose` still uses the viewport buffer as its compose
  buffer. With prefer-viewport nil it only sets `dismiss-on-send`
  buffer-locally, so send dismisses rather than kills
  (`agent-shell.el:1937-1975`). The viewport buffer exists in both setups;
  prefer-viewport only decides who routes into it.
- `agent-shell-insert` from a non-shell, non-viewport buffer goes to the
  shell prompt (`agent-shell.el:13003-13010`).
- `agent-shell-send-region` / `send-dwim` insert when
  `agent-shell--can-insert-into-prompt-p` (idle, or busy with a live
  persistent prompt; `agent-shell-prompt.el:172-189`). Otherwise they read a
  prompt in the minibuffer and send it (`agent-shell.el:13012-13029`).
- `agent-shell-prompt-queue-edit` uses the minibuffer, not the viewport
  (`agent-shell-prompt-queue.el:905-912`).
- With `agent-shell-persistent-prompt-enabled` nil, there is no place to type
  in the shell during a turn. The viewport compose buffer is still available
  (`agent-shell-prompt.el:57-60`).

## 5. Bill's Doom config today

All in `config.org`:

- `agent-shell-prefer-viewport-interaction` `t` (`:5192`).
- `agent-shell-session-strategy 'prompt` (`:5195`). The viewport waits for
  `session-selected` before showing (`agent-shell.el:1513-1534`).
- `agent-shell-display-action nil`, so Doom popup rules place buffers
  (`:5201`).
- Shell and viewport share one tile of the bottom popup row, keyed by the
  shell name with the viewport suffix stripped (`:5209-5219`). Rule:
  bottom, size 0.5, `:select t`, `:quit nil` (`:5227-5238`).
  agent-shell-side buffers go to the right edge (`:5246-5251`).
- Fire-and-forget compose from ordinary buffers:
  - `dismiss-on-send` is made not permanent-local (`:5286`).
  - It is set again from `agent-shell-viewport-edit-mode-hook` for the
    pending viewport (`:5300-5325`).
  - `agent-shell-prompt-compose` is advised to set it only when called
    outside a shell or viewport (`:5327-5346`).
  - `agent-shell-viewport--dismiss` is advised to keep the shell window
    and return to the origin workspace (`:5348-5410`).
- `+agent-shell-compose` picks a shell (through `agent-shell-vertico`) and
  opens its compose pop-up in that shell's workspace (`:5412-5437`).
- Edit mode starts in evil insert state (`:5480`). It is a Doom "real"
  buffer (`:5473-5475`), with smartparens pairs (`:5460-5470`) and a capf
  setup (`:4779-4786`).
- Bindings: `SPC k c` `+agent-shell-compose`, `SPC k '` toggle, `SPC k r`
  `agent-shell-vertico-send-region` (wraps `agent-shell-send-region`,
  `agent-shell-vertico.el:1154-1157`) (`:5550-5565`). In the shell, `gc`
  `agent-shell-prompt-compose` (`:5799`).
- Not set (defaults apply): `agent-shell-busy-submit-default-function`
  (steer), `agent-shell-persistent-prompt-enabled` (`t`),
  `agent-shell-prompt-queue-merge` (`t`), `agent-shell-viewport-dismiss-on-send`
  (nil globally).

## Trade-offs that follow from these facts

- **One slot per session.** The compose buffer is the only edit-mode
  surface for a session in Bill's setup. A review there shares it with
  ad-hoc prompts, `send-region`, queue edits (which erase it) and
  agent-shell-side hand-backs.
- **Name coupling.** Finding the review from the session means finding the
  viewport by name. A rename breaks it, and a restart starts a new empty
  one.
- **No silent append.** Adding a note through the public path selects the
  viewport window. Appending without focus means writing into another
  package's buffer directly.
- **Content gone on send.** Every send clears the buffer or switches it to
  view mode. "Edit then send" works. "Send and keep the review" does not.
- **Disposition reset.** Each append resets queue/steer intent unless the
  caller copies it back, as agent-shell-side does.
- **Free send keys.** A draft in the compose buffer gets send, queue, steer
  and override routing, plus history and completion, at no cost. An own
  buffer can reach the same routing with `agent-shell--prompt-send`, or by
  handing its text to `--show-buffer :override`/`:append` when the user
  wants to edit before sending.
- **Format.** The compose buffer is `text-mode` with a `line-prefix` of two
  spaces (`viewport.el:2091-2092`). It is not a Markdown mode.

## 03a section 5, checked against `70616c4`

- Line numbers are right or off by a few lines.
  `shell-maker-submit` is at `agent-shell.el:12966-12967`, not `12965-12966`.
  `agent-shell-send-region` is at `13012-13029`, not `13009-13025`.
- Correction: 03a calls the sender "about 10 lines, using
  `agent-shell-insert`" (`03a-fit-check.md:22`, `:146`). Under Bill's
  prefer-viewport `t`, `agent-shell-insert` called from a Magit or file
  buffer goes to `--show-buffer`. That selects the viewport, and it errors on
  `:submit` and `:no-focus` (section 3). The caveat at `03a:127` ("Busy, try
  later") applies only to the non-viewport path.
- Still true: from a non-shell buffer, `agent-shell--shell-buffer` resolves
  the project's first shell (`agent-shell.el:11648-11652`). A per-session
  target must be passed explicitly. `agent-shell--read-shell-buffer` is at
  `agent-shell.el:2140`.

## Unverified

- Working-tree cleanliness of the source repos. `git status` on them was
  refused in this sandbox, so the SHAs above are the `main` refs, and the
  files read may include uncommitted edits.
- The experiments used a fake shell buffer outside `agent-shell-mode`, with
  header and position stubbed and busy state overridden. No real ACP
  session, popup rule, evil or Doom hook was involved.
- The `agent-shell.el:2898-2905` wipe (first prompt with no client) was read,
  not run. Whether it can happen in practice depends on how often a viewport
  holding a draft exists before the shell's first prompt.
- How Doom's `+popup-display-buffer-tiled-fn` and `:select t` interact with
  `--show-buffer`'s `select-window` when called from a Magit buffer in
  another workspace was not checked.
- agent-shell-vertico's `--target-shell` and its send commands were not
  read beyond the `send-region` wrapper.
