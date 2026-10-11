# agent-shell-notes

Collect review notes in Emacs and send them to an
[agent-shell](https://github.com/xenodium/agent-shell) session as one
prompt.

Select text in a Magit diff, a file, a Dired listing, an agent-shell
transcript or any other buffer, write a remark, and keep going. The remarks
collect in one global review. From the review, mark some or all, pick a
live agent-shell session, and send them as one prompt rendered in the wire
format of a chosen agent app (Claude desktop, Codex, omp), optionally
followed by a free-text request.

Notes live only in the running Emacs. They are not saved across restarts,
and they do not follow the source text when it is edited or redrawn.

## Requirements

- Emacs 29.1 or later.
- agent-shell and markdown-mode.
- Magit is optional. Without it, Magit diffs are not a capture source.

The package calls agent-shell internals (`agent-shell--prompt-send`,
`agent-shell--read-shell-buffer`, the viewport compose buffer). It is
developed and tested against
[liaowang11/agent-shell](https://github.com/liaowang11/agent-shell) and
[liaowang11/acp.el](https://github.com/liaowang11/acp.el), the forks CI
uses. Upstream agent-shell is untested.

## Install

The package is not on a package archive. With `package-vc` (Emacs 29.1+):

```elisp
(package-vc-install "https://github.com/liaowang11/agent-shell-notes")
```

With Doom, in `packages.el`:

```elisp
(package! agent-shell-notes
  :recipe (:host github :repo "liaowang11/agent-shell-notes"))
```

Then load it, for example with `(require 'agent-shell-notes)` or
`use-package`. The entry commands are autoloaded.

## Use

Three commands start everything:

| Command | What it does |
| --- | --- |
| `agent-shell-notes-capture` | Capture a note from the current buffer: the region, else the current line. Opens a popup to write the remark. |
| `agent-shell-notes-review` | Show the review buffer `*agent-shell-notes*`. |
| `agent-shell-notes-send-all` | Send every note that is not archived, plus the request, without opening the review. With `C-u`, put the prompt in the target's compose buffer instead. |

The package binds no global keys and adds nothing to Magit or agent-shell
maps. Suggested bindings:

```elisp
(keymap-global-set "C-c n c" #'agent-shell-notes-capture)
(keymap-global-set "C-c n r" #'agent-shell-notes-review)
(keymap-global-set "C-c n s" #'agent-shell-notes-send-all)
```

Other global commands:

| Command | What it does |
| --- | --- |
| `agent-shell-notes-restore-last` | Undo the review side of the last send or compose: removed notes come back, archived notes get their old tags, marks and request return. Nothing is unsent. One level only. |
| `agent-shell-notes-set-style` | Set `agent-shell-notes-style` for this Emacs session. |
| `agent-shell-notes-set-after-send` | Set `agent-shell-notes-after-send` for this Emacs session. |

### What a capture takes

The first entry of `agent-shell-notes-sources` whose predicate matches the
buffer captures:

- **transcript**: an agent-shell buffer or its viewport. The region, else
  the current line, as Markdown, with the session and turn.
- **magit**: a hunk in a Magit diff or status buffer. The selected lines
  with their `+`/`-` prefixes, or the whole hunk with point on `@@`. A
  region may cross hunks but not files. Merge diffs are refused.
- **dired**: the marked files, else the file at point; with a region, the
  files on its lines. Paths only.
- **file**: the lines the region touches, else the current line.
- **buffer**: any other buffer, same extent as a file.

### The capture popup

`*agent-shell-notes capture*` shows the location and quote at the top,
read-only, and takes the note below.

| Key | Effect |
| --- | --- |
| `C-c C-c` | Save the note. An empty note is saved as a quote-only note. |
| `C-c C-k` | Abort without asking. |
| `TAB` | On the quote: unfold or fold it. Elsewhere: markdown-mode's `TAB`. |

Running `agent-shell-notes-capture` while a popup is open switches to it.
Under evil the popup opens in insert state.

### The review

`*agent-shell-notes*` groups notes by file, Dired directory, transcript turn
or buffer. The `# Request` section at the end takes ordinary typing; its
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

`C-c C-c` and `C-c C-r` also work from the request body.

Edit mode makes the note texts writable, like `wdired-mode`; headings,
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

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `agent-shell-notes-sources` | transcript, magit, dired, file, buffer | Capture sources tried in order, each `(SYMBOL PREDICATE EXTRACT)`. Add a new mode's entry before `buffer`, which matches everything. |
| `agent-shell-notes-style` | `claude` | Wire format of a send: `claude` (Claude desktop), `codex` (Codex app) or `omp` (oh-my-pi `/annotate`). |
| `agent-shell-notes-after-send` | `remove` | What a send does to the sent notes: `remove`, `archive` (keep them dimmed, tagged `sent to <session>`) or `keep`. |
| `agent-shell-notes-mark-indicator` | `fringe` | How a mark shows: `fringe` (a `*` in the margin on a terminal) or `background`. |
| `agent-shell-notes-fence-languages` | common extensions | File extension to code fence language, e.g. `el` to `elisp`. Unlisted files use the major mode name, else `text`. |
| `agent-shell-notes-capture-display-action` | bottom, height 0.3 | `display-buffer` action for the capture popup. |
| `agent-shell-notes-review-display-action` | nil | `display-buffer` action for the review. |
| `agent-shell-notes-client` | the agent-shell client | Where notes are sent; see below. |
| `agent-shell-notes-agent-shell-disposition` | nil | How a send reaches a busy shell: nil (agent-shell's default), `queue` or `steer`. Does not apply to compose, which keeps the compose buffer's own choice. |

Faces: `agent-shell-notes-location` (location lines), `agent-shell-notes-tag`
(tags such as `unstaged` or `sent to <session>`),
`agent-shell-notes-archived` (archived notes), `agent-shell-notes-mark`
(the mark indicator or background).

`agent-shell-notes-client` is a plist of functions, so another chat front
end can receive notes:

| Slot | Signature |
| --- | --- |
| `:read-session` | `(HINT) -> SESSION`, HINT is `(:projects LIST :last SESSION)` |
| `:send` | `(SESSION TEXT)`; returning normally means sent |
| `:compose` | `(SESSION TEXT)`, optional; without it `C-u` sends are refused |
| `:name` | `(SESSION) -> string` |
| `:project` | `(SESSION) -> directory`, decides relative or absolute paths |
| `:session-id` | `(SESSION) -> string`, decides which transcript notes are the session's own |
| `:turn-count` | `(SESSION) -> integer`, decides "last reply" in `omp` |

## Doom and other configurations

The package is Doom-agnostic. Leader keys, `set-popup-rule!` entries for
`*agent-shell-notes*` and `*agent-shell-notes capture*`, and evil state
choices belong in your own config. For example:

```elisp
(map! :leader
      (:prefix ("n a" . "agent notes")
       :desc "Capture" "c" #'agent-shell-notes-capture
       :desc "Review"  "r" #'agent-shell-notes-review
       :desc "Send all" "s" #'agent-shell-notes-send-all))
(set-popup-rule! "^\\*agent-shell-notes capture\\*" :side 'bottom :size 0.3 :select t)
```

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
- Jumping to a transcript or buffer note whose buffer is gone, or to an
  old-side or committed Magit note whose diff buffer is gone, reports an
  error instead of reopening it.

## Development

```sh
make check        # byte-compile with warnings as errors, then batch ERT
make live-check   # real agent round trip, by hand only
```

Dependency checkouts are Makefile variables (`FORKS_DIR`,
`STRAIGHT_REPOS`, or per repo such as `AGENT_SHELL_DIR`). CI runs
`make check` on Emacs 29.1 and snapshot.

`make live-check` starts a real claude-agent-acp session and spends tokens.
It needs `claude-agent-acp` on `PATH` and a logged-in Claude account.

Golden files under `tests/golden/` are the exact text a send produces.
Some lines end in significant trailing spaces (empty quote lines are
`> `, for example in `claude-reply-escape.txt` and
`claude-mixed-batch.txt`). Do not let your editor strip trailing
whitespace in that directory.

## License

MIT. See `LICENSE`.
