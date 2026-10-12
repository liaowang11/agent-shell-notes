# agent-shell-notes

[![CI](https://github.com/liaowang11/agent-shell-notes/actions/workflows/ci.yml/badge.svg)](https://github.com/liaowang11/agent-shell-notes/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Emacs 29.1+](https://img.shields.io/badge/Emacs-29.1%2B-7F5AB6?logo=gnuemacs&logoColor=white)](https://www.gnu.org/software/emacs/)

Collect review notes anywhere in Emacs and send them to an
[agent-shell](https://github.com/xenodium/agent-shell) session as one
prompt.

Select text in a Magit diff, a file, a Dired listing, an agent-shell
transcript or any other buffer, write a remark, and keep going. The remarks
collect in one global review. From the review, mark some or all, pick a
live agent-shell session, and send them as one prompt in the format of a
chosen agent app (Claude desktop, Codex, omp), optionally followed by a
free-text request.

Notes live only in the running Emacs. They are not saved across restarts,
and they do not follow the source text when it is edited or redrawn.

## Contents

- [Demo](#demo)
- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Customization](#customization)
- [Q&A](#qa)
- [Known limitations](#known-limitations)
- [Development](#development)
- [Star history](#star-history)
- [License](#license)

## Demo

<!--
  PLACEHOLDER: no demo recorded yet, and docs/assets/demo.mp4 does not exist.

  To record: start a screen recording (macOS: Cmd-Shift-5, "Record Selected
  Portion"), capture two or three notes (a Magit hunk, a file line, a line of
  an agent reply), open the review, mark them, add a request and send with
  C-c C-c. Aim for under 60 seconds.

  To shrink a .mov:
    ffmpeg -i demo.mov -vf "scale=1280:-2" -c:v libx264 -crf 28 -an docs/assets/demo.mp4

  To embed: GitHub reliably shows a player only for video uploaded through
  its web UI. Drag the mp4 into an issue or PR comment, copy the
  https://github.com/user-attachments/assets/... URL it produces, and put
  that URL on a line of its own here, in place of the <video> tag below.
  A repository-relative path may show only as a link.
-->

<video src="docs/assets/demo.mp4" controls muted width="100%"></video>

If the player does not load, see [docs/assets/demo.mp4](docs/assets/demo.mp4).

## Requirements

- Emacs 29.1 or later.
- [agent-shell](https://github.com/xenodium/agent-shell) and
  [markdown-mode](https://github.com/jrblevin/markdown-mode).
- Optional: `markdown-ts-mode` (built into Emacs 31) with the `markdown`
  and `markdown-inline` tree-sitter grammars. When both are there, the
  review and the popup use it; otherwise they use markdown-mode. See
  [Which Markdown mode does the review use?](#which-markdown-mode-does-the-review-use)
- [Magit](https://magit.vc) is optional. Without it, Magit diffs are not a
  capture source.

The package calls agent-shell internals (`agent-shell--prompt-send`,
`agent-shell--read-shell-buffer`, the viewport compose buffer). It is
developed and tested against
[liaowang11/agent-shell](https://github.com/liaowang11/agent-shell) and
[liaowang11/acp.el](https://github.com/liaowang11/acp.el), the forks CI
uses. Upstream agent-shell is untested. See
[Do I need the agent-shell fork?](#do-i-need-the-agent-shell-fork)

## Install

The package is **not on MELPA** or any other package archive. Install it
from GitHub. None of the recipes below install the agent-shell fork; set
that up separately (see the [Q&A](#do-i-need-the-agent-shell-fork)).

**package-vc** (Emacs 29.1+):

```elisp
(package-vc-install "https://github.com/liaowang11/agent-shell-notes")
```

**use-package with `:vc`** (Emacs 30.1+, where `use-package` has `:vc`):

```elisp
(use-package agent-shell-notes
  :vc (:url "https://github.com/liaowang11/agent-shell-notes" :rev :newest))
```

`:rev :newest` tracks the latest commit; without it `:vc` looks for a
release.

**straight.el**:

```elisp
(straight-use-package
 '(agent-shell-notes :type git :host github :repo "liaowang11/agent-shell-notes"))
```

**Doom Emacs**, in `packages.el`:

```elisp
(package! agent-shell-notes
  :recipe (:host github :repo "liaowang11/agent-shell-notes"))
```

then run `doom sync`.

Then load it, for example with `(require 'agent-shell-notes)` or
`use-package`. The entry commands are autoloaded.

## Quick start

1. Bind the three entry commands. The package binds no global keys:

   ```elisp
   (keymap-global-set "C-c n c" #'agent-shell-notes-capture)
   (keymap-global-set "C-c n r" #'agent-shell-notes-review)
   (keymap-global-set "C-c n s" #'agent-shell-notes-send-all)
   ```

2. Start an agent-shell session (`M-x agent-shell`).
3. In any buffer, select some text (or leave point on a line) and press
   `C-c n c`. Write your remark in the popup and press `C-c C-c`.
4. Repeat in other buffers: diffs, files, the agent's last reply.
5. Press `C-c n r` to open the review. Mark the notes to send with `m`, or
   all of them with `t`. Optionally type a request in the `# Request`
   section at the end.
6. Press `C-c C-c`, pick the session, and the marked notes and the request
   go out as one prompt. With nothing marked, `C-c C-c` sends only the note
   at point. Or skip the review and press `C-c n s` to send every note.

Press `w` in the review to copy the prompt without sending it, or
`C-u C-c C-c` to put it in the session's compose buffer and edit it first.

## Usage

### Commands

| Command | What it does |
| --- | --- |
| `agent-shell-notes-capture` | Capture a note from the current buffer: the region, else the current line. Opens a popup to write the remark. |
| `agent-shell-notes-review` | Show the review buffer `*agent-shell-notes*`. |
| `agent-shell-notes-send-all` | Send every note that is not archived, plus the request, without opening the review. With `C-u`, put the prompt in the target's compose buffer instead. |
| `agent-shell-notes-restore-last` | Undo the review side of the last send or compose: removed notes come back, archived notes get their old tags, marks and request return. Nothing is unsent. One level only. |
| `agent-shell-notes-set-style` | Set `agent-shell-notes-style` for this Emacs session. |
| `agent-shell-notes-set-after-send` | Set `agent-shell-notes-after-send` for this Emacs session. |

### What a capture takes

The first entry of `agent-shell-notes-sources` whose predicate matches the
buffer captures:

| Source | Matches | Captures |
| --- | --- | --- |
| `transcript` | An agent-shell buffer or its viewport. | The region, else the current line, as Markdown, with the session and turn. |
| `magit` | A hunk in a Magit diff or status buffer. | The selected lines with their `+`/`-` prefixes, or the whole hunk with point on `@@`. A region may cross hunks but not files. Merge diffs are refused. |
| `dired` | A Dired buffer. | The marked files, else the file at point; with a region, the files on its lines. Paths only. |
| `file` | A buffer visiting a file. | The lines the region touches, else the current line. |
| `buffer` | Any other buffer. | Same extent as a file. |

### The capture popup

`*agent-shell-notes capture*` shows the location and quote at the top,
read-only, and takes the note below.

| Key | Effect |
| --- | --- |
| `C-c C-c` | Save the note. An empty note is saved as a quote-only note. |
| `C-c C-k` | Abort without asking. |
| `TAB` | On the quote: unfold or fold it. Elsewhere: the Markdown mode's `TAB`. |

Running `agent-shell-notes-capture` while a popup is open switches to it.
Under evil the popup opens in insert state.

### The review

`*agent-shell-notes*` groups notes by file, Dired directory, transcript turn
or buffer. The header line shows the mode (`Review` or `Edit`), how many
notes, groups, marked and sent notes there are, and the main keys:

```
Review │ 3 notes · 2 groups · 1 marked │ C-c C-c send  C-c C-e edit
```

The `# Request` section at the end takes ordinary typing; its
text follows the notes in the next send. Elsewhere the buffer is read-only
and single keys act on notes:

| Key | Command | Effect |
| --- | --- | --- |
| `n` / `p` | `agent-shell-notes-next-note` / `-previous-note` | Move between notes. |
| `m` / `u` | `agent-shell-notes-mark` / `-unmark` | Mark or unmark the note at point, or every note the region touches. |
| `t` | `agent-shell-notes-toggle-marks` | Toggle all marks; archived notes are skipped. |
| `U` | `agent-shell-notes-unmark-all` | Clear all marks. |
| `k` | `agent-shell-notes-delete` | Delete the note at point, no confirmation. |
| `D` | `agent-shell-notes-delete-marked` | Delete the marked notes, after confirming. |
| `x` | `agent-shell-notes-purge-archived` | Delete every archived note. |
| `e` | `agent-shell-notes-edit` | Enter edit mode at this note's text. |
| `C-c C-e`, `C-x C-q` | `agent-shell-notes-edit-mode` | Enter edit mode. |
| `RET`, `mouse-1` | `agent-shell-notes-jump` | On a location line or group heading: jump to the source and flash it. |
| `TAB` | `agent-shell-notes-toggle-quote` | Fold or unfold the quote (folded after 6 lines). |
| `C-c C-c` | `agent-shell-notes-send` | Send the marked notes, else the note at point, plus the request, to a picked session. |
| `C-u C-c C-c` | `agent-shell-notes-send` | Put the same prompt in the session's compose buffer to edit before sending. |
| `w` | `agent-shell-notes-copy` | Copy the rendered prompt to the kill ring. Changes nothing. |
| `C-c C-r` | `agent-shell-notes-restore-last` | Undo the review side of the last send. |
| `g` | `agent-shell-notes-redraw` | Redraw. |
| `q` | `quit-window` | Quit. |

`C-c C-c` and `C-c C-r` also work from the request body. There the
single keys, `RET` and `TAB` step aside, so they type (or, under evil,
run evil's commands). `agent-shell-notes-in-request-p` tells whether
point is in the body; use it as a `menu-item` `:filter` to give your own
review bindings the same behavior.

**Edit mode** makes the note texts writable, like `wdired-mode`; headings,
locations and quotes stay read-only and the single keys above are off.

| Key | Effect |
| --- | --- |
| `C-c C-c`, `C-c C-e`, `C-x C-q` | Save the changed texts and leave. |
| `C-c C-k` | Revert and leave. |

Emptying a text keeps the note as a quote-only note.

### Sending

The picker lists every live agent-shell session: the last target first,
then sessions in the notes' projects, then the rest. After a send or
compose, marks and the request clear, and `agent-shell-notes-after-send`
decides what happens to the notes that went out. A session whose agent has
not started yet is refused with "Starting agent, please wait".

## Customization

All options are in the `agent-shell-notes` customization group
(`M-x customize-group RET agent-shell-notes`).

| Option | Default | Meaning |
| --- | --- | --- |
| `agent-shell-notes-markdown-mode` | `auto` | The mode the review and popup derive from: `auto` (markdown-ts-mode when it can run, else markdown-mode), `markdown-ts-mode` (the same, but warn on fallback) or `markdown-mode`. Read when the package loads: set it before, or reload the package after a change. |
| `agent-shell-notes-style` | `claude` | Format of a send: `claude` (Claude desktop), `codex` (Codex app) or `omp` (oh-my-pi `/annotate`). |
| `agent-shell-notes-after-send` | `remove` | What a send does to the sent notes: `remove`, `archive` (keep them dimmed, tagged `sent to <session>`) or `keep`. |
| `agent-shell-notes-agent-shell-disposition` | nil | How a send reaches a busy shell: nil (agent-shell's default), `queue` or `steer`. Does not apply to compose, which keeps the compose buffer's own choice. |
| `agent-shell-notes-mark-indicator` | `fringe` | How a mark shows: `fringe` (a `*` in the margin on a terminal) or `background`. |
| `agent-shell-notes-sources` | transcript, magit, dired, file, buffer | Capture sources tried in order, each `(SYMBOL PREDICATE EXTRACT)`. Add a new mode's entry before `buffer`, which matches everything. |
| `agent-shell-notes-fence-languages` | common extensions | File extension to code fence language, e.g. `el` to `elisp`. Unlisted files use the major mode name, else `text`. |
| `agent-shell-notes-capture-display-action` | bottom, height 0.3 | `display-buffer` action for the capture popup. |
| `agent-shell-notes-review-display-action` | nil | `display-buffer` action for the review. |
| `agent-shell-notes-client` | the agent-shell client | Where notes are sent; see [Sending to another front end](#can-i-send-notes-somewhere-other-than-agent-shell). |

Faces:

| Face | Used for |
| --- | --- |
| `agent-shell-notes-location` | Location lines. |
| `agent-shell-notes-tag` | Tags such as `unstaged` or `sent to <session>`. |
| `agent-shell-notes-archived` | Archived notes. |
| `agent-shell-notes-mark` | The mark indicator or background. |

### Example: plain Emacs

```elisp
(use-package agent-shell-notes
  :vc (:url "https://github.com/liaowang11/agent-shell-notes" :rev :newest)
  :bind (("C-c n c" . agent-shell-notes-capture)
         ("C-c n r" . agent-shell-notes-review)
         ("C-c n s" . agent-shell-notes-send-all))
  :custom
  (agent-shell-notes-style 'codex)
  (agent-shell-notes-after-send 'archive)
  (agent-shell-notes-agent-shell-disposition 'queue)
  (agent-shell-notes-review-display-action
   '(display-buffer-in-side-window (side . right) (window-width . 0.4))))
```

### Example: Doom Emacs

The package is Doom-agnostic. Leader keys, popup rules and evil states
belong in your own `config.el`:

```elisp
(use-package! agent-shell-notes
  :defer t
  :config
  (setq agent-shell-notes-after-send 'archive))

(map! :leader
      (:prefix ("n a" . "agent notes")
       :desc "Capture"  "c" #'agent-shell-notes-capture
       :desc "Review"   "r" #'agent-shell-notes-review
       :desc "Send all" "s" #'agent-shell-notes-send-all))

(set-popup-rule! "^\\*agent-shell-notes capture\\*" :side 'bottom :size 0.3 :select t)

;; The review uses single-letter keys; let them through under evil.
(after! evil
  (evil-set-initial-state 'agent-shell-notes-review-mode 'emacs))
```

## Q&A

### Is it on MELPA?

No. Install it from GitHub with one of the recipes under
[Install](#install).

### Do I need the agent-shell fork?

The package calls agent-shell internals: `agent-shell--prompt-send` with a
`:disposition` argument, `agent-shell--read-shell-buffer`,
`agent-shell-viewport--show-buffer` for compose and `agent-shell--turns`.
Internals can change without notice. CI clones
[liaowang11/agent-shell](https://github.com/liaowang11/agent-shell) (branch
`main`, unpinned) and [liaowang11/acp.el](https://github.com/liaowang11/acp.el),
and that is what the package is tested against. Upstream agent-shell is
untested: it may work, or a send or compose may fail. To use the forks in
Doom:

```elisp
(package! agent-shell :recipe (:host github :repo "liaowang11/agent-shell"))
(package! acp :recipe (:host github :repo "liaowang11/acp.el"))
```

### When is anything sent to the agent, and what exactly is sent?

Nothing leaves Emacs until you send: `C-c C-c` in the review or
`agent-shell-notes-send-all`. `C-u` with either puts the prompt in the
session's compose buffer instead, where you can edit it before sending.
`w` copies the prompt to the kill ring and changes nothing; paths in the
copy are relative, since there is no target.

A send is one prompt: each note's location, its quote and your remark,
then the request. With the default `claude` style, two notes on a file
plus a request render as:

````text
In `src/foo.el` at line 3:
```elisp
(let ((cache (make-hash-table)))
```
hoist the cache

In `src/foo.el` at lines 10-11:
```elisp
  (puthash key value cache)
  cache)
```


fix both, then run make check
````

The second note is quote-only, so it has no remark. Dired notes send paths
only, never file contents.

### Which style should I pick?

Each style copies the format an agent app uses when it sends review
comments: `claude` for the Claude desktop app, `codex` for the Codex app,
`omp` for oh-my-pi's `/annotate`. Every style is plain Markdown text, so
any agent can read any of them. Set the default with
`agent-shell-notes-style`, or switch for this session with
`M-x agent-shell-notes-set-style`.

### The agent is busy. What happens when I send?

By default agent-shell decides (`agent-shell-busy-submit-default-function`).
Set `agent-shell-notes-agent-shell-disposition` to `queue` or `steer` to
choose yourself. Compose keeps whatever the compose buffer already uses.

### I sent the wrong notes. Can I undo?

`agent-shell-notes-restore-last` (`C-c C-r` in the review) puts the review
back as it was: removed notes return, archived notes get their old tags,
and marks and the request come back. It cannot unsend the prompt. It
keeps one level only.

### Why don't `n`, `m`, `k` work in the review under evil?

Evil's normal state shadows the review's single-letter keys. The package
adds no evil bindings by design. Use Emacs state in the review (see the
[Doom example](#example-doom-emacs)), or bind the commands in your evil
config. The capture popup already opens in insert state.

The request body works in any state: in normal state, `i` enters insert
state there and `j`/`k` move as usual. To keep an evil binding of your
own from firing in the body, wrap it like the package does:

```elisp
(evil-define-key* 'normal agent-shell-notes-review-mode-map
  "j" `(menu-item "" agent-shell-notes-next-note
                  :filter ,(lambda (cmd)
                             (unless (agent-shell-notes-in-request-p)
                               cmd))))
```

### Which Markdown mode does the review use?

`markdown-ts-mode` when it can run: Emacs 31 or later ships it (turned
off by default, but present), and the `markdown` and `markdown-inline`
grammars must be installed (`M-x markdown-ts-mode-install-parsers`).
Otherwise markdown-mode, which stays a dependency. Set
`agent-shell-notes-markdown-mode` to `markdown-mode` to never use the
tree-sitter mode.

The choice is made once, when the package loads. After changing the
option, run `M-x load-library RET agent-shell-notes` and reopen the
review and the popup.

Both modes run their own hooks: under markdown-ts-mode,
`markdown-ts-mode-hook` runs and `markdown-mode-hook` does not, though
`derived-mode-p` still reports `markdown-mode`. A setting in
`markdown-mode-hook` (evil-markdown, say) does not reach the review
then.

The package keys behave the same under both. What differs is the
Markdown mode's own keys:

- `S-TAB` (`markdown-shifttab`), which folds every group from anywhere,
  has no markdown-ts-mode equivalent. In its place, `TAB` on a group
  heading folds that group and `S-TAB` on a heading cycles all of them
  (outline cycling). Under markdown-mode `TAB` on a heading does nothing.
  A redraw unfolds the groups.
- In the request body and the popup's note area, `TAB` and `RET` are
  markdown-ts-mode's: `TAB` cycles a heading and does nothing elsewhere,
  `RET` continues list items and block quotes.
- markdown-ts-mode's command mode inside code blocks (`TAB` indenting in
  the block's language) is turned off in both buffers, because the
  quotes are read-only code blocks and `TAB` folds them.
- Quote code is highlighted in its language by default under
  markdown-ts-mode; under markdown-mode only with
  `markdown-fontify-code-blocks-natively`.

### The session picker ignores "last target first". Why?

agent-shell-vertico re-sorts the picker by recency, so the package's order
(last target, then same project, then the rest) does not show.

### I had text typed at the agent-shell prompt. Where did it go?

A send does not check the prompt. Text already typed there ends up in
front of the notes. Clear the prompt before sending, or send with `C-u`
and review the compose buffer.

### Do notes survive a restart, or follow my edits?

No. Notes live only in the running Emacs, and they do not follow the
source text when it is edited or when Magit or agent-shell redraws it.

### How do I capture from a mode that isn't supported?

Add an entry to `agent-shell-notes-sources` before `buffer`, which matches
everything. Each entry is `(SYMBOL PREDICATE EXTRACT)`; `C-h v
agent-shell-notes-sources` documents what EXTRACT must return.

### Can I send notes somewhere other than agent-shell?

Yes. `agent-shell-notes-client` is a plist of functions, so another chat
front end can receive notes:

| Slot | Signature |
| --- | --- |
| `:read-session` | `(HINT) -> SESSION`, HINT is `(:projects LIST :last SESSION)` |
| `:send` | `(SESSION TEXT)`; returning normally means sent |
| `:compose` | `(SESSION TEXT)`, optional; without it `C-u` sends are refused |
| `:name` | `(SESSION) -> string` |
| `:project` | `(SESSION) -> directory`, decides relative or absolute paths |
| `:session-id` | `(SESSION) -> string`, decides which transcript notes are the session's own |
| `:turn-count` | `(SESSION) -> integer`, decides "last reply" in `omp` |

### My editor broke the golden tests. Why?

Golden files under `tests/golden/` are the exact text a send produces.
Some lines end in trailing spaces that matter (empty quote lines are
`> `, for example in `claude-reply-escape.txt` and
`claude-mixed-batch.txt`). Do not let your editor strip trailing
whitespace in that directory.

## Known limitations

- With agent-shell-vertico, the picker is re-sorted by recency, so the
  package's order (last target, then same project) does not show.
- Under evil, normal state in the review shadows the single-letter keys.
  Use Emacs state there, or bind the commands in your evil config.
- Text already typed at the agent-shell prompt is not guarded; a send
  puts it in front of the notes.
- Running `M-x agent-shell-notes-edit-mode` while editing leaves edit mode
  and drops the edits; use `C-c C-c` or `C-c C-k`.
- Restore-last keeps one level. After deleting other notes, a restored note
  may land one place off.
- Jumping to a note whose source buffer is gone reopens a file, Dired
  directory or the agent-shell viewport when it can. It reports an error
  for a transcript note whose session is gone, a `buffer` note, and an
  old-side or committed Magit note.

## Development

```sh
make check        # byte-compile with warnings as errors, then batch ERT
make test-ts      # the same ERT suite under markdown-ts-mode (Emacs 31+)
make live-check   # real agent round trip, by hand only
```

`make check` runs the suite under the markdown-mode fallback. `make
test-ts` runs it again with the tree-sitter grammars on
`treesit-extra-load-path`, so the review and popup derive from
markdown-ts-mode. It reads the grammars from `TREESIT_TS_DIR`, default
`~/.config/emacs/.local/etc/tree-sitter` (Doom's directory), and fails
at once if they cannot load. `make check-ts` is compile plus `test-ts`.
Tests that only make sense under markdown-ts-mode skip in the fallback
run.

Dependency checkouts are Makefile variables (`FORKS_DIR`,
`STRAIGHT_REPOS`, or per repo such as `AGENT_SHELL_DIR`). CI runs
`make check` on Emacs 29.1 and snapshot, without grammars, so it covers
the fallback only.

`make live-check` starts a real claude-agent-acp session and spends tokens.
It needs `claude-agent-acp` on `PATH` and a logged-in Claude account.

Design notes are in [DESIGN.md](DESIGN.md); vocabulary is in
[GLOSSARY.md](GLOSSARY.md). Keep the trailing spaces in `tests/golden/`
(see the [Q&A](#my-editor-broke-the-golden-tests-why)).

## Star history

<a href="https://star-history.com/#liaowang11/agent-shell-notes&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=liaowang11/agent-shell-notes&type=Date&theme=dark" />
    <img alt="Star history chart for liaowang11/agent-shell-notes" src="https://api.star-history.com/svg?repos=liaowang11/agent-shell-notes&type=Date" />
  </picture>
</a>

## License

MIT. See [LICENSE](LICENSE).
