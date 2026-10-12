;;; agent-shell-notes.el --- Collect review notes and send them to agent-shell -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; Copyright (C) 2026 Bill and contributors

;; Author: Bill
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell) (markdown-mode))
;; Keywords: convenience, tools
;; URL: https://github.com/liaowang11/agent-shell-notes

;;; Commentary:

;; Select text in a Magit diff, a file, a Dired listing, an agent-shell
;; transcript or any other buffer, write a remark, and keep going.  The
;; remarks collect in one global review.  From the review, mark some or all,
;; pick a live agent-shell session, and send them as one prompt rendered in
;; the wire format of a chosen agent app (Claude desktop, Codex, omp),
;; optionally followed by a free-text request.
;;
;; Entry commands: `agent-shell-notes-capture', `agent-shell-notes-review'
;; and `agent-shell-notes-send-all'.  The package binds no global keys;
;; README.md suggests bindings and lists the review keys and options.
;;
;; Notes live only in the running Emacs.  Magit is optional: the Magit
;; source is skipped when Magit is not loaded.

;;; Code:

(require 'agent-shell)
(require 'markdown-mode)
(require 'project)
(require 'dired)

(defgroup agent-shell-notes nil
  "Collect review notes and send them to agent-shell."
  :group 'tools
  :prefix "agent-shell-notes-")

(defcustom agent-shell-notes-markdown-mode 'auto
  "The Markdown mode the review and the capture popup derive from.
`auto' takes `markdown-ts-mode' when it can run: the mode exists
\(Emacs 31 and later) and the `markdown' and `markdown-inline'
tree-sitter grammars are installed.  Otherwise it takes
`markdown-mode'.  `markdown-ts-mode' is the same, except it warns
when it falls back.

The choice is made when the package loads.  Set this before that;
after a change, reload the package (\\[load-library] agent-shell-notes)
and reopen the review and the popup."
  :type '(choice (const :tag "markdown-ts-mode when it can run" auto)
                 (const :tag "markdown-ts-mode, warn on fallback"
                        markdown-ts-mode)
                 (const :tag "markdown-mode" markdown-mode)))

(declare-function treesit-ready-p "treesit" (language &optional quiet))

(defun agent-shell-notes--markdown-ts-ready-p ()
  "Return non-nil when `markdown-ts-mode' can run in this Emacs.
The mode alone is not enough: without both grammars it turns the
buffer into `text-mode'."
  (and (require 'markdown-ts-mode nil t)
       (treesit-ready-p '(markdown markdown-inline) t)))

(defun agent-shell-notes--choose-markdown-mode ()
  "Return the mode `agent-shell-notes-markdown-mode' picks in this Emacs."
  (cond ((eq agent-shell-notes-markdown-mode 'markdown-mode) 'markdown-mode)
        ((agent-shell-notes--markdown-ts-ready-p) 'markdown-ts-mode)
        (t (when (eq agent-shell-notes-markdown-mode 'markdown-ts-mode)
             (display-warning 'agent-shell-notes
                              "markdown-ts-mode cannot run (no mode or no \
`markdown'/`markdown-inline' grammar); using markdown-mode"))
           'markdown-mode)))

(defvar agent-shell-notes--markdown-parent nil
  "The Markdown mode the package's modes derive from, chosen at load.")

(setq agent-shell-notes--markdown-parent
      (agent-shell-notes--choose-markdown-mode))

;; The modes derive from this alias.  `define-derived-mode' needs a
;; literal parent; `derived-mode-p' follows the alias to the real mode
;; on Emacs 29.1 as on 31, and calling it runs the real mode, hooks
;; included.
(defalias 'agent-shell-notes--markdown-mode agent-shell-notes--markdown-parent
  "The Markdown mode in `agent-shell-notes--markdown-parent'.")

;; Emacs 30 and later cache a mode's parents, the alias's included; a
;; reload with another choice must drop the stale chain.
(when (fboundp 'derived-mode-set-parent)
  (derived-mode-set-parent 'agent-shell-notes--markdown-mode nil))

(defun agent-shell-notes--markdown-map ()
  "Return the keymap of `agent-shell-notes--markdown-parent'."
  (symbol-value (derived-mode-map-name agent-shell-notes--markdown-parent)))

(defvar markdown-ts-code-block-context-mode)
(declare-function markdown-ts-code-block-context-mode "markdown-ts-mode"
                  (&optional arg))

(defun agent-shell-notes--markdown-setup ()
  "Adjust the Markdown parent for the review and the popup.
markdown-ts-mode turns on a minor mode whose map takes `TAB' and
`RET' inside code blocks; the quotes are read-only code blocks whose
`TAB' folds, so turn it off."
  (when (bound-and-true-p markdown-ts-code-block-context-mode)
    (markdown-ts-code-block-context-mode -1)))

(defface agent-shell-notes-location
  '((t :inherit font-lock-comment-face))
  "Face of a note's location line.")

(defface agent-shell-notes-tag
  '((t :inherit font-lock-constant-face))
  "Face of a note's tags in the review, such as `unstaged'.")

;;;; Notes

(defvar agent-shell-notes--notes nil
  "Every note of this Emacs session, oldest first.
A note is an alist with the keys `:id', `:source', `:project',
`:location', `:quote', `:text', `:markers', `:archived' and
`:created'.  The review is drawn from this list and nothing is read
back from a buffer.")

(defvar agent-shell-notes--next-id 0
  "The last note id handed out.")

(defun agent-shell-notes--project ()
  "Return the project root of the current buffer, else `default-directory'."
  (if-let* ((project (project-current nil)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

(defun agent-shell-notes--add (note)
  "Give NOTE the next id, append it to the note list and return it."
  (setq note (cons (cons :id (setq agent-shell-notes--next-id
                                   (1+ agent-shell-notes--next-id)))
                   note))
  (setq agent-shell-notes--notes
        (append agent-shell-notes--notes (list note)))
  note)

;;;; Sources

(defun agent-shell-notes--line-extent ()
  "Return (BEG END START-LINE END-LINE) of the lines to capture.
The current line, or every line the active region touches.  A region
ending at the start of a line does not touch that line."
  (let (beg end)
    (if (use-region-p)
        (let ((rbeg (region-beginning))
              (rend (region-end)))
          (save-excursion
            (goto-char rend)
            (when (and (bolp) (> rend rbeg))
              (backward-char))
            (setq end (line-end-position))
            (goto-char rbeg)
            (setq beg (line-beginning-position))))
      (setq beg (line-beginning-position)
            end (line-end-position)))
    (list beg end (line-number-at-pos beg t) (line-number-at-pos end t))))

(defun agent-shell-notes--file-extract ()
  "Extract a `file' note from the current buffer."
  (pcase-let ((`(,beg ,end ,start ,last) (agent-shell-notes--line-extent)))
    (list :location (list :file buffer-file-name :start start :end last)
          :quote (buffer-substring-no-properties beg end)
          :beg beg
          :end end)))

;;;;; Magit

;; Magit is optional: nothing here runs unless a Magit buffer is current,
;; and Magit is loaded by then.
(declare-function magit-section-at "magit-section" (&optional position))
(declare-function magit-diff-hunk-line "magit-diff" (section goto-from))
(declare-function magit-diff-type "magit-diff" (&optional section))
(declare-function eieio-oref "eieio-core" (obj slot))
(defvar magit-buffer-diff-range)
(defvar magit-buffer-revision)

(defun agent-shell-notes--magit-slot (section slot)
  "Return SLOT of the Magit SECTION."
  (eieio-oref section slot))

(defun agent-shell-notes--magit-file-section (section)
  "Return the file section SECTION is or belongs to, else nil."
  (pcase (and section (agent-shell-notes--magit-slot section 'type))
    ('file section)
    ('hunk (agent-shell-notes--magit-slot section 'parent))))

(defun agent-shell-notes--magit-p ()
  "Return non-nil in a Magit buffer with a diff section under point or region."
  (and (derived-mode-p 'magit-section-mode)
       (fboundp 'magit-diff-hunk-line)
       (pcase-let ((`(,beg ,end) (agent-shell-notes--line-extent)))
         (or (agent-shell-notes--magit-file-section (magit-section-at beg))
             (agent-shell-notes--magit-file-section (magit-section-at end))))))

(defun agent-shell-notes--magit-lines (beg end)
  "Return the hunks and body lines touched by the lines from BEG to END.
The value is (HUNKS . LINES): HUNKS the hunk sections in order, LINES
a list of (POS HUNK CHAR) for each hunk body line, CHAR its prefix.
Signal `user-error' when the lines cross files or touch no hunk."
  (let (files hunks lines)
    (save-excursion
      (goto-char beg)
      (while (progn
               (let* ((pos (point))
                      (section (magit-section-at pos))
                      (file (agent-shell-notes--magit-file-section section)))
                 (when (and file (not (memq file files)))
                   (push file files))
                 (when (and section
                            (eq (agent-shell-notes--magit-slot section 'type)
                                'hunk))
                   (unless (memq section hunks)
                     (push section hunks))
                   (when (>= pos (agent-shell-notes--magit-slot
                                  section 'content))
                     (push (list pos section (char-after pos)) lines))))
               (and (zerop (forward-line 1))
                    (not (eobp))
                    (<= (point) end)))))
    (when (cdr files)
      (user-error "The region crosses files"))
    (unless hunks
      (user-error "Point is not in a hunk"))
    (when (seq-some (lambda (h) (agent-shell-notes--magit-slot h 'combined))
                    hunks)
      (user-error "Merge diffs are not supported"))
    (cons (nreverse hunks) (nreverse lines))))

(defun agent-shell-notes--magit-hunk-body (hunk)
  "Return (POS HUNK CHAR) for every body line of HUNK."
  (let ((end (agent-shell-notes--magit-slot hunk 'end))
        lines)
    (save-excursion
      (goto-char (agent-shell-notes--magit-slot hunk 'content))
      (while (< (point) end)
        (push (list (point) hunk (char-after)) lines)
        (forward-line 1)))
    (nreverse lines)))

(defun agent-shell-notes--magit-line (line goto-from)
  "Return the number Magit maps body LINE to, old side if GOTO-FROM."
  (unless line
    (user-error "No diff line selected"))
  (save-excursion
    (goto-char (car line))
    (or (magit-diff-hunk-line (nth 1 line) goto-from)
        (user-error "Magit cannot map this line"))))

(defun agent-shell-notes--magit-extract ()
  "Extract a `magit' note from the hunk lines at point or in the region.
Point on a hunk heading with no region takes the whole hunk.  The side
is old when every line is a deletion, else new.  Line numbers are
Magit's mapping of the first and last selected line of that side: a
heading maps wrong, and a `-' line maps to the next new line."
  (pcase-let* ((`(,beg ,end) (agent-shell-notes--line-extent))
               (`(,hunks . ,lines) (agent-shell-notes--magit-lines beg end))
               (whole (null lines))
               (lines (or lines (mapcan #'agent-shell-notes--magit-hunk-body
                                        hunks)))
               (sided (seq-remove (lambda (line) (eq (nth 2 line) ?\\))
                                  lines))
               (old (and sided
                         (seq-every-p (lambda (line) (eq (nth 2 line) ?-))
                                      sided)))
               (mixed (and (seq-some (lambda (line) (eq (nth 2 line) ?-))
                                     sided)
                           (seq-some (lambda (line) (eq (nth 2 line) ?+))
                                     sided)
                           t))
               (own (if old
                        sided
                      (seq-remove (lambda (line) (eq (nth 2 line) ?-))
                                  sided)))
               (start (agent-shell-notes--magit-line (car own) old))
               (last (agent-shell-notes--magit-line (car (last own)) old))
               (file-section (agent-shell-notes--magit-file-section
                              (car hunks)))
               (type (magit-diff-type (car hunks))))
    (when whole
      (setq beg (agent-shell-notes--magit-slot (car hunks) 'start)
            end (agent-shell-notes--magit-slot (car (last hunks)) 'end)))
    (list :location
          (list :file (or (and old (agent-shell-notes--magit-slot
                                    file-section 'source))
                          (agent-shell-notes--magit-slot file-section 'value))
                :side (if old 'old 'new)
                :start start
                :end last
                :hunks (mapcar (lambda (hunk)
                                 (buffer-substring-no-properties
                                  (agent-shell-notes--magit-slot hunk 'start)
                                  (agent-shell-notes--magit-slot hunk 'end)))
                               hunks)
                :type type
                :rev (and (eq type 'committed)
                          (or magit-buffer-revision magit-buffer-diff-range))
                :mixed mixed)
          :quote (mapconcat (lambda (line)
                              (save-excursion
                                (goto-char (car line))
                                (buffer-substring-no-properties
                                 (line-beginning-position)
                                 (line-end-position))))
                            lines "\n")
          :beg beg
          :end end)))

;;;;; Transcript

(defun agent-shell-notes--transcript-shell ()
  "Return the shell buffer of the current transcript buffer, or nil.
That is the buffer itself in a shell, or a viewport page's shell."
  (cond ((derived-mode-p 'agent-shell-mode) (current-buffer))
        ((derived-mode-p 'agent-shell-viewport-view-mode)
         (agent-shell-viewport--shell-buffer))))

(defun agent-shell-notes--fragment-kind (state tool-calls)
  "Return the block kind of a fragment whose ui state is STATE.
TOOL-CALLS is the shell's `:tool-calls' alist.  The qualified id is
<namespace>-<block-id> and the namespace may contain `-', so block
ids are matched at the end.  Return nil for chrome."
  (let ((qid (or (map-elt state :qualified-id) "")))
    (cond
     ((string-suffix-p "-agent_message_chunk" qid) 'message)
     ((string-match-p "-agent_thought_chunk\\(?:-[0-9]+\\)?\\'" qid) 'thought)
     ((string-suffix-p "-user_message_chunk" qid) 'prompt)
     ((string-suffix-p "-plan" qid) 'plan)
     ((string-match-p "-permission-" qid) 'permission)
     ;; An activity group heads the tool calls under it.
     ((eq (map-elt state :kind) 'group) 'tool)
     ((seq-find (lambda (id) (string-suffix-p (concat "-" id) qid))
                (map-keys tool-calls))
      'tool))))

(defun agent-shell-notes--prompt-text-p (pos)
  "Return non-nil when POS, outside any fragment, is a user prompt.
A shell prompt runs from the prompt string to the end-of-prompt
marker; a viewport page marks its echoed prompt."
  (or (get-text-property pos 'agent-shell-viewport-prompt)
      (get-text-property pos 'shell-maker--marker)
      (memq 'comint-highlight-prompt
            (ensure-list (get-text-property pos 'font-lock-face)))
      (when-let* ((marker (text-property-any pos (point-max)
                                             'shell-maker--marker t)))
        ;; Inside the input when no prompt string starts between POS
        ;; and the next marker; response text has the next turn's
        ;; prompt in between, or no marker after it.
        (let ((p pos) found)
          (while (and (not found) (< p marker))
            (setq found (memq 'comint-highlight-prompt
                              (ensure-list (get-text-property
                                            p 'font-lock-face)))
                  p (next-single-property-change
                     p 'font-lock-face nil marker)))
          (not found)))))

(defun agent-shell-notes--transcript-kind (beg end tool-calls)
  "Return the block kind of the text from BEG to END.
TOOL-CALLS is the shell's `:tool-calls' alist.  Text of several kinds
is `mixed'; with none, `message'."
  (let ((pos beg) kinds)
    (while (< pos end)
      (let ((next (min end
                       (next-single-property-change
                        pos 'agent-shell-ui-state nil end)
                       (next-single-property-change
                        pos 'font-lock-face nil end)
                       (next-single-property-change
                        pos 'shell-maker--marker nil end)
                       (next-single-property-change
                        pos 'agent-shell-viewport-prompt nil end))))
        (unless (string-blank-p (buffer-substring-no-properties pos next))
          (when-let* ((kind (if-let* ((state (get-text-property
                                              pos 'agent-shell-ui-state)))
                                (agent-shell-notes--fragment-kind
                                 state tool-calls)
                              (and (agent-shell-notes--prompt-text-p pos)
                                   'prompt))))
            (cl-pushnew kind kinds)))
        (setq pos next)))
    (cond ((null kinds) 'message)
          ((cdr kinds) 'mixed)
          (t (car kinds)))))

(defun agent-shell-notes--transcript-turn (shell pos)
  "Return the 1-based turn at POS of the current transcript buffer.
SHELL is its shell.  A viewport page is one turn: the viewport's
cached position, which every page change refreshes."
  (map-elt (if (eq shell (current-buffer))
               (save-excursion (goto-char pos) (agent-shell--turn-position))
             (agent-shell-viewport--position))
           :current))

(defun agent-shell-notes--transcript-extract ()
  "Extract a `transcript' note from a shell or viewport buffer.
The extent is the region, else the current line; the quote is its
Markdown as `agent-shell-copy-as-markdown' would give it."
  (let* ((shell (agent-shell-notes--transcript-shell))
         (region (use-region-p))
         (beg (if region (region-beginning) (line-beginning-position)))
         (end (if region (region-end) (line-end-position)))
         (turn (agent-shell-notes--transcript-turn shell beg))
         (turn-end (agent-shell-notes--transcript-turn shell end))
         (prompt (when turn
                   (with-current-buffer shell
                     (map-elt (agent-shell--turn-at-index turn) :prompt)))))
    (list :location
          (list :session-id (agent-shell-session-id :shell-buffer shell)
                :shell (buffer-name shell)
                :turn turn
                :kind (agent-shell-notes--transcript-kind
                       beg end (map-elt (buffer-local-value
                                         'agent-shell--state shell)
                                        :tool-calls))
                :prompt (when prompt
                          (car (split-string (substring-no-properties prompt)
                                             "\n")))
                :turn-end (unless (eql turn turn-end) turn-end))
          :quote (string-trim (agent-shell--buffer-markdown-substring beg end)
                              "[\n]+" "[\n]+")
          :beg beg
          :end end)))

(defun agent-shell-notes--dired-p ()
  "Return non-nil in a Dired buffer."
  (derived-mode-p 'dired-mode))

(defun agent-shell-notes--dired-extract ()
  "Extract a `dired' note: paths only, no quote.
With a region, the files on the lines it touches; else the marked
files, else the file at point."
  (pcase-let* ((`(,beg ,end) (agent-shell-notes--line-extent))
               (files
                (if (use-region-p)
                    (save-excursion
                      (goto-char beg)
                      (let (files)
                        (while (progn
                                 ;; As dired's own region marking, skip
                                 ;; . and ..
                                 (when-let* ((file (dired-get-filename nil t))
                                             ((not (looking-at-p dired-re-dot))))
                                   (push file files))
                                 (and (zerop (forward-line 1))
                                      (<= (point) end))))
                        (nreverse files)))
                  (dired-get-marked-files))))
    (unless files
      (user-error "No file at point"))
    (list :location (list :files files
                          :directory (expand-file-name default-directory))
          :quote nil
          :beg beg
          :end end)))

(defun agent-shell-notes--buffer-extract ()
  "Extract a `buffer' note: the region's lines, else the current line."
  (pcase-let ((`(,beg ,end ,start ,last) (agent-shell-notes--line-extent)))
    (list :location (list :buffer (buffer-name) :mode major-mode
                          :start start :end last)
          :quote (buffer-substring-no-properties beg end)
          :beg beg
          :end end)))

(defcustom agent-shell-notes-sources
  '((transcript agent-shell-notes--transcript-shell
                agent-shell-notes--transcript-extract)
    (magit agent-shell-notes--magit-p agent-shell-notes--magit-extract)
    (dired agent-shell-notes--dired-p agent-shell-notes--dired-extract)
    (file buffer-file-name agent-shell-notes--file-extract)
    (buffer always agent-shell-notes--buffer-extract))
  "Source types tried in order by `agent-shell-notes-capture'.
Each entry is (SYMBOL PREDICATE EXTRACT).  The first entry whose
PREDICATE, called with no arguments in the buffer being captured,
returns non-nil captures.  EXTRACT is then called the same way and
returns a plist:

  :location  the note's location, as described for SYMBOL's source
  :quote     the text copied from the source, or nil
  :beg :end  buffer positions of the captured extent, kept as markers

SYMBOL becomes the note's `:source'.  The last entry, `buffer',
matches every buffer; add a new mode's entry before it.  The review
and the styles show a source they do not know as a `buffer' note, so
its location should carry `:buffer', `:mode', `:start' and `:end', as
`agent-shell-notes--buffer-extract' returns."
  :type '(repeat (list (symbol :tag "Source")
                       (function :tag "Predicate")
                       (function :tag "Extract"))))

(defun agent-shell-notes--extract ()
  "Return a note without id for the current buffer, its text empty."
  (let ((entry (seq-find (lambda (entry) (funcall (nth 1 entry)))
                         agent-shell-notes-sources)))
    (unless entry
      (user-error "No note source matches this buffer"))
    (let ((plist (funcall (nth 2 entry))))
      (list (cons :source (car entry))
            (cons :project (agent-shell-notes--project))
            (cons :location (plist-get plist :location))
            (cons :quote (plist-get plist :quote))
            (cons :text "")
            (cons :markers (list (current-buffer)
                                 (copy-marker (plist-get plist :beg))
                                 (copy-marker (plist-get plist :end) t)))
            (cons :archived nil)
            (cons :created (current-time))))))

;;;; Display helpers

(defun agent-shell-notes--line-range (location)
  "Return \"N\" or \"S-E\", the lines of LOCATION."
  (let ((start (plist-get location :start))
        (end (plist-get location :end)))
    (if (eql start end)
        (number-to-string start)
      (format "%d-%d" start end))))

(defun agent-shell-notes--range-string (location)
  "Return \"line N\" or \"lines S-E\" for LOCATION."
  (concat (if (eql (plist-get location :start) (plist-get location :end))
              "line "
            "lines ")
          (agent-shell-notes--line-range location)))

(defun agent-shell-notes--directory (dir)
  "Return DIR expanded, as a directory name."
  (file-name-as-directory (expand-file-name dir)))

(defun agent-shell-notes--note-file (note)
  "Return the absolute path of NOTE's file.
A `magit' note stores it relative to the note's project."
  (expand-file-name (plist-get (alist-get :location note) :file)
                    (alist-get :project note)))

(defun agent-shell-notes--dired-names (note &optional dir)
  "Return the files of Dired NOTE, comma-joined.
Relative to DIR, default the note's project."
  (mapconcat (lambda (file)
               (file-relative-name file (or dir (alist-get :project note))))
             (plist-get (alist-get :location note) :files)
             ", "))

(defun agent-shell-notes--fence (text)
  "Return a backtick fence longer than any backtick run in TEXT."
  (let ((longest 2)
        (start 0))
    (while (string-match "`+" text start)
      (setq longest (max longest (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    (make-string (1+ longest) ?`)))

;;;; Rendering

(defcustom agent-shell-notes-style 'claude
  "The wire format a send renders notes in."
  :type '(choice (const :tag "Claude desktop" claude)
                 (const :tag "Codex app" codex)
                 (const :tag "oh-my-pi /annotate" omp)))

;;;###autoload
(defun agent-shell-notes-set-style (style)
  "Set `agent-shell-notes-style' to STYLE for this Emacs session."
  (interactive
   (list (intern (completing-read
                  (format "Style (now %s): " agent-shell-notes-style)
                  (mapcar (lambda (choice) (symbol-name (car (last choice))))
                          (cdr (get 'agent-shell-notes-style 'custom-type)))
                  nil t))))
  (setq agent-shell-notes-style style)
  (message "Style: %s" style))

(defcustom agent-shell-notes-fence-languages
  '(("el" . "elisp") ("py" . "python") ("ts" . "typescript")
    ("tsx" . "tsx") ("js" . "javascript") ("jsx" . "jsx")
    ("md" . "markdown") ("org" . "org") ("sh" . "bash") ("bash" . "bash")
    ("zsh" . "zsh") ("rb" . "ruby") ("rs" . "rust") ("go" . "go")
    ("c" . "c") ("h" . "c") ("cc" . "cpp") ("cpp" . "cpp") ("hpp" . "cpp")
    ("java" . "java") ("kt" . "kotlin") ("swift" . "swift")
    ("json" . "json") ("yaml" . "yaml") ("yml" . "yaml")
    ("toml" . "toml") ("nix" . "nix") ("lua" . "lua") ("sql" . "sql")
    ("html" . "html") ("css" . "css") ("vue" . "vue"))
  "File extension to fence language, tried before `auto-mode-alist'."
  :type '(alist :key-type (string :tag "Extension")
                :value-type (string :tag "Language")))

(defun agent-shell-notes--fence-language (file)
  "Return the fence language of FILE.
From `agent-shell-notes-fence-languages', else the name of the major
mode `auto-mode-alist' picks without `-ts-mode' or `-mode', else
\"text\"."
  (or (cdr (assoc (file-name-extension file)
                  agent-shell-notes-fence-languages))
      (let ((mode (assoc-default file auto-mode-alist #'string-match)))
        ;; (MODE NON-NIL) entries; a lambda stays a lambda.
        (when (and (consp mode) (not (functionp mode)))
          (setq mode (car mode)))
        (when (and mode (symbolp mode))
          (replace-regexp-in-string "\\(-ts\\)?-mode\\'" ""
                                    (symbol-name mode))))
      "text"))

(defconst agent-shell-notes--claude-blank
  "[[:blank:]\v\f­​-‏⁠-⁯﻿⠀]"
  "A blank as the Claude desktop serializer counts one.")

(defun agent-shell-notes--claude-mentions (text)
  "Return TEXT with each mention-like `@' made fullwidth.
An `@' is mention-like when a word character follows it and none
precedes it."
  (replace-regexp-in-string "\\(?:^\\|[^[:alnum:]_]\\)\\(@\\)[[:alnum:]_]"
                            "＠" text t t 1))

(defun agent-shell-notes--claude-path (path)
  "Return PATH sanitized for a Claude location line."
  (agent-shell-notes--claude-mentions
   (string-replace "`" "'" (replace-regexp-in-string "[\r\n]+" " " path))))

(defun agent-shell-notes--claude-snippet (quote)
  "Return QUOTE trimmed and sanitized for a Claude snippet.
Lines that read like a location line, a `Reply ...:' line or an
attachment marker get a `> ' in place of their leading blanks."
  (let ((blank agent-shell-notes--claude-blank))
    (replace-regexp-in-string
     (concat "^" blank "*"
             "\\(?:In\\b.*\\bat lines? [0-9]"
             "\\|Reply\\b.*:" blank "*$"
             "\\|<!-- attach\\)")
     (lambda (line)
       (concat "> " (replace-regexp-in-string (concat "\\`" blank "*") ""
                                              line)))
     (agent-shell-notes--trim-lines quote)
     t t)))

(defun agent-shell-notes--note-path (note project &optional file)
  "Return the path of NOTE's file as sent to a target in PROJECT.
Relative to the note's project, or absolute when PROJECT, if non-nil,
is another project.  FILE, if non-nil, is the file instead of the
note's `:file'."
  (let ((file (or file (agent-shell-notes--note-file note)))
        (own (alist-get :project note)))
    (if (and project
             (not (equal (agent-shell-notes--directory project)
                         (agent-shell-notes--directory own))))
        file
      (file-relative-name file own))))

(defun agent-shell-notes--diff-side-lines (note)
  "Return the quote lines of `magit' NOTE on its side, prefixes stripped.
The new side keeps `+' and context lines, so a mixed selection drops
its deletions; the old side keeps `-' lines."
  (let ((keep (if (eq (plist-get (alist-get :location note) :side) 'old)
                  '(?-)
                '(?+ ?\s))))
    (mapconcat (lambda (line) (substring line 1))
               (seq-filter (lambda (line)
                             (and (> (length line) 0)
                                  (memq (aref line 0) keep)))
                           (split-string (alist-get :quote note) "\n"))
               "\n")))

(defun agent-shell-notes--claude-file-block (note project)
  "Return the Claude block of file or `magit' NOTE for a target in PROJECT."
  (let* ((loc (alist-get :location note))
         (diff (eq (alist-get :source note) 'magit))
         (quote (if diff
                    (agent-shell-notes--diff-side-lines note)
                  (alist-get :quote note)))
         (text (alist-get :text note))
         (lines (list (format "In `%s` at %s%s:"
                              (agent-shell-notes--claude-path
                               (agent-shell-notes--note-path note project))
                              (agent-shell-notes--range-string loc)
                              (if (and diff (eq (plist-get loc :side) 'old))
                                  " (before changes)"
                                "")))))
    (when quote
      (let* ((snippet (agent-shell-notes--claude-snippet quote))
             (fence (agent-shell-notes--fence snippet)))
        (setq lines (append lines
                            (list (concat fence
                                          (agent-shell-notes--fence-language
                                           (plist-get loc :file)))
                                  snippet fence)))))
    (unless (string-empty-p text)
      (setq lines (append lines (list text))))
    (string-join lines "\n")))

(defun agent-shell-notes--other-session-quote (note)
  "Return the block of transcript NOTE from another session, any style.
A `> ' quote, then the note text after a blank line."
  (let ((text (alist-get :text note)))
    (concat (agent-shell-notes--block-quote (alist-get :quote note))
            (unless (string-empty-p text)
              (concat "\n\n" text)))))

(defun agent-shell-notes--claude-reply-text (text)
  "Return note TEXT as the body of a Claude reply block.
Trimmed; a line that is a reply marker is escaped as `&lt;'; runs of
three or more newlines become two."
  (replace-regexp-in-string
   "\n\\{3,\\}" "\n\n"
   (replace-regexp-in-string "^<!-- reply\\(?: [0-9]+\\)? -->$"
                             (lambda (line) (concat "&lt;" (substring line 1)))
                             (string-trim text) t t)
   t t))

(defun agent-shell-notes--claude-replies (notes)
  "Return NOTES as Claude reply blocks, joined by a blank line.
The first marker carries the number of blocks."
  (let ((count (length notes))
        (first t))
    (mapconcat (lambda (note)
                 (prog1
                     (concat (if first
                                 (format "<!-- reply %d -->" count)
                               "<!-- reply -->")
                             "\n"
                             (agent-shell-notes--block-quote
                              (alist-get :quote note))
                             "\n\n"
                             (agent-shell-notes--claude-reply-text
                              (alist-get :text note)))
                   (setq first nil)))
               notes "\n\n")))

(defconst agent-shell-notes--claude-max-replies 99
  "Claude sends at most this many reply blocks.")

(defun agent-shell-notes--claude-dired-block (note project)
  "Return the Claude block of Dired NOTE for a target in PROJECT."
  (let ((text (alist-get :text note))
        (about (format "About %s:"
                       (mapconcat
                        (lambda (file)
                          (format "`%s`" (agent-shell-notes--claude-path
                                          (agent-shell-notes--note-path
                                           note project file))))
                        (plist-get (alist-get :location note) :files)
                        ", "))))
    (if (string-empty-p text)
        about
      (concat about "\n" text))))

(defun agent-shell-notes--claude-buffer-block (note)
  "Return the Claude block of `buffer' NOTE.
The buffer has no file to name a language, so the fence says `text'."
  (let* ((loc (alist-get :location note))
         (snippet (agent-shell-notes--claude-snippet (alist-get :quote note)))
         (fence (agent-shell-notes--fence snippet))
         (text (alist-get :text note)))
    (string-join
     (append (list (format "In buffer `%s` (%s) at %s:"
                           (agent-shell-notes--claude-path
                            (plist-get loc :buffer))
                           (plist-get loc :mode)
                           (agent-shell-notes--range-string loc))
                   (concat fence "text") snippet fence)
             (unless (string-empty-p text) (list text)))
     "\n")))

(defun agent-shell-notes--claude-block (note project)
  "Return the Claude block of NOTE for a target in PROJECT."
  (pcase (alist-get :source note)
    ((or 'file 'magit) (agent-shell-notes--claude-file-block note project))
    ('transcript (agent-shell-notes--other-session-quote note))
    ('dired (agent-shell-notes--claude-dired-block note project))
    ;; `buffer', and any source added by the user.
    (_ (agent-shell-notes--claude-buffer-block note))))

(defun agent-shell-notes--render (notes request project
                                         &optional session-id turn-count)
  "Return NOTES and REQUEST rendered in `agent-shell-notes-style'.
NOTES are in review order.  PROJECT is the target's project, or nil
when there is no target; a note from another project gets an absolute
path.  SESSION-ID is the target's session id: transcript notes from
that session are own-session notes (`claude' places them first as
reply blocks).  TURN-COUNT is the target's number of turns."
  (pcase agent-shell-notes-style
    ('codex (agent-shell-notes--codex-render notes request project
                                             session-id))
    ('omp (agent-shell-notes--omp-render notes request project
                                         session-id turn-count))
    (_ (agent-shell-notes--claude-render notes request project session-id))))

(defun agent-shell-notes--own-session-p (note session-id)
  "Non-nil when NOTE is a transcript note from session SESSION-ID.
SESSION-ID nil, no target, makes every note foreign."
  (and session-id
       (eq (alist-get :source note) 'transcript)
       (equal session-id
              (plist-get (alist-get :location note) :session-id))))

(defun agent-shell-notes--claude-render (notes request project session-id)
  "Return NOTES and REQUEST in the `claude' style.
PROJECT and SESSION-ID are as for `agent-shell-notes--render'."
  (let* ((replies (seq-take
                   (seq-filter
                    (lambda (note)
                      (and (agent-shell-notes--own-session-p note session-id)
                           (not (string-empty-p
                                 (string-trim (alist-get :text note))))))
                    notes)
                   agent-shell-notes--claude-max-replies))
         (rest (mapconcat
                (lambda (note)
                  (agent-shell-notes--claude-block note project))
                (seq-remove (lambda (note) (memq note replies)) notes)
                "\n\n")))
    (string-join (seq-remove #'string-empty-p
                             (list (agent-shell-notes--claude-replies replies)
                                   rest
                                   (string-trim request)))
                 "\n\n\n")))

;;;;; Codex

(defun agent-shell-notes--codex-workspace (note project)
  "Return NOTE's `Workspace:' line for a target in PROJECT, or nil.
Only when PROJECT is non-nil and differs from the note's project."
  (let ((own (agent-shell-notes--directory (alist-get :project note))))
    (when (and project
               (not (equal own (agent-shell-notes--directory project))))
      (concat "Workspace: " (directory-file-name own)))))

(defun agent-shell-notes--codex-fenced (lang text)
  "Return TEXT in a fence with info string LANG."
  (let ((fence (agent-shell-notes--fence text)))
    (concat fence lang "\n" text "\n" fence)))

(defun agent-shell-notes--codex-comment (note n project)
  "Return the `## User Comment N' block of NOTE for a target in PROJECT.
NOTE is a `magit', `file', `dired' or `buffer' note."
  (let* ((loc (alist-get :location note))
         (body
          (pcase (alist-get :source note)
            ('magit
             (list (concat "File: " (plist-get loc :file))
                   (agent-shell-notes--codex-workspace note project)
                   ;; A mixed selection is a new-side one.
                   (if (eq (plist-get loc :side) 'old) "Side: L" "Side: R")
                   (concat "Lines: " (agent-shell-notes--line-range loc))
                   "Diff hunk:"
                   (agent-shell-notes--codex-fenced
                    "diff" (mapconcat (lambda (hunk)
                                        (string-remove-suffix "\n" hunk))
                                      (plist-get loc :hunks) "\n"))))
            ('file
             ;; Always relative: another project adds `Workspace:'.
             (list (concat "File: " (agent-shell-notes--note-path note nil))
                   (agent-shell-notes--codex-workspace note project)
                   (concat "Lines: " (agent-shell-notes--line-range loc))
                   (agent-shell-notes--codex-fenced
                    (agent-shell-notes--fence-language (plist-get loc :file))
                    (agent-shell-notes--trim-lines (alist-get :quote note)))))
            ('dired
             (list (concat "Files: " (agent-shell-notes--dired-names note))
                   (agent-shell-notes--codex-workspace note project)))
            ;; `buffer', and any source added by the user.  The buffer
            ;; has no path, so no `Workspace:'.
            (_
             (list (format "Buffer: %s (%s)"
                           (plist-get loc :buffer) (plist-get loc :mode))
                   (concat "Lines: " (agent-shell-notes--line-range loc))
                   (agent-shell-notes--codex-fenced
                    "text"
                    (agent-shell-notes--trim-lines (alist-get :quote note))))))))
    (string-join (append (list (format "## User Comment %d" n))
                         (delq nil body)
                         (list "Comment:" (alist-get :text note)))
                 "\n")))

(defconst agent-shell-notes--codex-annotations-instruction
  "Each item contains text selected from an earlier Codex response and may include a user comment. Treat items as Annotation 1, Annotation 2, and so on in array order. Use every selection as context and address every comment. For every annotation you address, include its inline directive `:codex-annotation{index=\"N\"}`, where N is its one-based array position (for example, `:codex-annotation{index=\"1\"}`). Do not use unstructured annotation labels."
  "The Codex app's instruction under `# Response annotations:', verbatim.")

(defun agent-shell-notes--codex-annotations (notes)
  "Return the `# Response annotations:' section of transcript NOTES.
A JSON array of `text' and, when the note text is not empty,
`annotation'.  The app's `source' field is dropped."
  (let ((json (json-serialize
               (vconcat
                (mapcar (lambda (note)
                          (let ((text (string-trim (alist-get :text note))))
                            `((text . ,(agent-shell-notes--trim-lines
                                        (alist-get :quote note)))
                              ,@(unless (string-empty-p text)
                                  `((annotation . ,text))))))
                        notes)))))
    (string-join
     (list "# Response annotations:"
           agent-shell-notes--codex-annotations-instruction
           "<response-annotations>"
           ;; Emacs 30 and later return UTF-8 bytes.
           (if (multibyte-string-p json) json (decode-coding-string json 'utf-8))
           "</response-annotations>")
     "\n")))

(defun agent-shell-notes--codex-render (notes request project session-id)
  "Return NOTES and REQUEST in the `codex' style for a target in PROJECT.
Sections in the Codex app's order: transcript notes from SESSION-ID as
response annotations, quotes from other sessions, diff comments for
the rest, then `## My request:'."
  (let* ((n 0)
         (own (seq-filter (lambda (note)
                            (agent-shell-notes--own-session-p note session-id))
                          notes))
         (quotes (seq-filter (lambda (note)
                               (and (eq (alist-get :source note) 'transcript)
                                    (not (memq note own))))
                             notes))
         (comments
          (mapcar (lambda (note)
                    (agent-shell-notes--codex-comment note (cl-incf n) project))
                  (seq-remove (lambda (note)
                                (eq (alist-get :source note) 'transcript))
                              notes)))
         (sections
          (append
           (when own (list (agent-shell-notes--codex-annotations own)))
           (mapcar #'agent-shell-notes--other-session-quote quotes)
           (when comments
             (list (string-join (cons "# Diff comments:" comments) "\n\n")))))
         (request (string-trim request)))
    (cond ((null sections) request)
          ((string-empty-p request)
           (string-trim-right (string-join sections "\n\n")))
          (t (string-join (append sections
                                  (list (concat "## My request:\n" request)))
                          "\n\n")))))

;;;; The omp style

(defconst agent-shell-notes--omp-diff-heading
  (concat "## Code Review Annotations\n\n"
          "Use these annotations as review notes; they are not"
          " independently validated findings.")
  "The heading omp's `/annotate code-review' paste mode opens with.")

(defun agent-shell-notes--trim-lines (text)
  "Return TEXT with trailing whitespace trimmed from every line."
  (mapconcat #'string-trim-right (split-string text "\n") "\n"))

(defun agent-shell-notes--omp-diff-note (note project)
  "Return the omp block of `magit' NOTE for a target in PROJECT."
  (let* ((loc (alist-get :location note))
         (path (agent-shell-notes--note-path note project))
         (quote (agent-shell-notes--trim-lines (alist-get :quote note)))
         (fence (agent-shell-notes--fence quote))
         (text (alist-get :text note)))
    (string-join
     (append
      (list (format "### %s — %s %s" path (plist-get loc :side)
                    (agent-shell-notes--line-range loc))
            (format "Path: `%s`" path)
            "")
      (mapcar (lambda (hunk)
                (format "Hunk: `%s`" (car (split-string hunk "\n"))))
              (plist-get loc :hunks))
      (list "" (concat fence "diff") quote fence)
      (unless (string-empty-p text) (list text)))
     "\n")))

(defun agent-shell-notes--omp-item (number quote text)
  "Return omp's numbered feedback item NUMBER on QUOTE with TEXT.
QUOTE nil makes it general feedback.  A quote holding a newline or a
backtick goes in a `text' fence, else inline in double quotes."
  (let ((quote (and quote (agent-shell-notes--trim-lines quote))))
    (string-join
     (append
      (if (not quote)
          (list (format "## %d. General feedback" number))
        (list (format "## %d. Feedback on:" number)
              (if (string-match-p "[\n`]" quote)
                  (let ((fence (agent-shell-notes--fence quote)))
                    (concat fence "text\n" quote "\n" fence))
                (format "\"%s\"" quote))))
      (unless (string-empty-p text) (list text)))
     "\n")))

(defun agent-shell-notes--omp-note (note project session-id turn-count number)
  "Return (HEADING NUMBERED BODY) for NOTE in the `omp' style.
HEADING is nil for a note that opens none; NUMBERED is non-nil when
BODY uses NUMBER.  PROJECT, SESSION-ID and TURN-COUNT are as for
`agent-shell-notes--render'."
  (let ((loc (alist-get :location note))
        (quote (alist-get :quote note))
        (text (alist-get :text note)))
    (pcase (alist-get :source note)
      ('magit (list agent-shell-notes--omp-diff-heading nil
                    (agent-shell-notes--omp-diff-note note project)))
      ((guard (agent-shell-notes--own-session-p note session-id))
       (let ((turn (plist-get loc :turn)))
         ;; A note captured before the first prompt has no turn: it is
         ;; never the last reply, and its heading names no number.
         (list (cond ((null turn) "# Feedback on Assistant message")
                     ((eql turn turn-count) "# Feedback on your last reply")
                     (t (format "# Feedback on Assistant message %d" turn)))
               t (agent-shell-notes--omp-item number quote text))))
      ('transcript (list nil nil
                         (agent-shell-notes--other-session-quote note)))
      ('file (list (format "# Feedback on %s"
                           (agent-shell-notes--note-path note project))
                   t (agent-shell-notes--omp-item number quote text)))
      ('dired (list (format "# Feedback on %s"
                            (mapconcat (lambda (file)
                                         (agent-shell-notes--note-path
                                          note project file))
                                       (plist-get loc :files) ", "))
                    t (agent-shell-notes--omp-item number nil text)))
      ;; `buffer', and any source added by the user.
      (_ (list (format "# Feedback on %s" (plist-get loc :buffer))
               t (agent-shell-notes--omp-item number quote text))))))

(defun agent-shell-notes--omp-render (notes request project session-id
                                            turn-count)
  "Return NOTES and REQUEST in the `omp' style.
Each note goes under its heading; consecutive notes with the same
heading share it.  Item numbers run across the send.  PROJECT,
SESSION-ID and TURN-COUNT are as for `agent-shell-notes--render'."
  (let ((number 1) sections heading)
    (dolist (note notes)
      (pcase-let ((`(,head ,numbered ,body)
                   (agent-shell-notes--omp-note note project session-id
                                                turn-count number)))
        (when numbered (setq number (1+ number)))
        (if (and head (equal head heading))
            (setcar sections (concat (car sections) "\n" body))
          (push (if head (concat head "\n" body) body) sections))
        (setq heading head)))
    (string-join (seq-remove #'string-empty-p
                             (list (string-join (nreverse sections) "\n\n")
                                   (string-trim request)))
                 "\n\n")))

;;;; Quote folding

(defconst agent-shell-notes--fold-lines 6
  "Quotes longer than this many lines are shown folded.")

(defvar-local agent-shell-notes--unfolded nil
  "Ids of review notes whose quote the user unfolded.")

(defvar-local agent-shell-notes--text-start nil
  "Marker at the start of the note area in the capture popup.")

(defun agent-shell-notes--fold-quote (beg end &optional open)
  "Fold the quote text between BEG and END after its sixth line.
With OPEN non-nil, create the fold opened.  Mark the text from BEG to
END with the `agent-shell-notes-field' property `quote'."
  (put-text-property beg end 'agent-shell-notes-field 'quote)
  (save-excursion
    (goto-char beg)
    (when (and (zerop (forward-line agent-shell-notes--fold-lines))
               (< (point) end))
      (let ((ov (make-overlay (1- (point)) end nil t)))
        (overlay-put ov 'agent-shell-notes-fold t)
        (overlay-put ov 'evaporate t)
        (unless open
          (overlay-put ov 'invisible 'agent-shell-notes-quote))))))

(defun agent-shell-notes--fold-overlay ()
  "Return the fold overlay of the quote that belongs to point, or nil.
In the review that is the quote of the note at point; in the capture
popup it is the popup's quote."
  (let* ((id (get-text-property (point) 'agent-shell-notes-id))
         (beg (if id (agent-shell-notes--note-start (point)) (point-min)))
         (end (if id
                  (or (next-single-property-change
                       (point) 'agent-shell-notes-id)
                      (point-max))
                (point-max))))
    (when (or id (derived-mode-p 'agent-shell-notes-capture-mode))
      (seq-find (lambda (ov) (overlay-get ov 'agent-shell-notes-fold))
                (overlays-in beg end)))))

(defun agent-shell-notes-toggle-quote ()
  "Fold or unfold the quote of the note at point.
In the note area of the capture popup, do what TAB does in Markdown."
  (interactive)
  (agent-shell-notes--refuse-in-request)
  (let ((ov (unless (and agent-shell-notes--text-start
                         (>= (point) agent-shell-notes--text-start))
              (agent-shell-notes--fold-overlay)))
        (id (get-text-property (point) 'agent-shell-notes-id)))
    (cond
     (ov
      (let ((open (overlay-get ov 'invisible)))
        (overlay-put ov 'invisible (unless open 'agent-shell-notes-quote))
        (when id
          (setq agent-shell-notes--unfolded
                (if open
                    (cons id agent-shell-notes--unfolded)
                  (delq id agent-shell-notes--unfolded))))))
     (agent-shell-notes--text-start
      (call-interactively (lookup-key (agent-shell-notes--markdown-map)
                                      (kbd "TAB")))))))

;;;; Locations and quotes

(defun agent-shell-notes--kind-name (kind)
  "Return the name the review shows for transcript block KIND."
  (if (eq kind 'message) "reply" (symbol-name kind)))

(defun agent-shell-notes--turn-string (location)
  "Return \"turn N\" or \"turns N-M\" for transcript LOCATION, or nil."
  (let ((turn (plist-get location :turn))
        (turn-end (plist-get location :turn-end)))
    (cond ((null turn) nil)
          (turn-end (format "turns %d-%d" turn turn-end))
          (t (format "turn %d" turn)))))

(defun agent-shell-notes--location-string (note)
  "Return the location line of NOTE for the capture popup."
  (let ((loc (alist-get :location note)))
    (pcase (alist-get :source note)
      ('transcript
       (string-join (delq nil (list (plist-get loc :shell)
                                    (agent-shell-notes--turn-string loc)
                                    (agent-shell-notes--kind-name
                                     (plist-get loc :kind))))
                    " — "))
      ((or 'file 'magit)
       (concat (file-relative-name (agent-shell-notes--note-file note)
                                   (alist-get :project note))
               " " (agent-shell-notes--range-string loc)))
      ('dired (agent-shell-notes--dired-names note))
      ;; `buffer', and any source added by the user.
      (_ (format "%s (%s) %s" (plist-get loc :buffer)
                 (plist-get loc :mode)
                 (agent-shell-notes--range-string loc))))))

(defun agent-shell-notes--insert-quote (note &optional open)
  "Insert NOTE's quote at point, folded unless OPEN, if it has one.
A transcript quote is a `> ' block; any other quote is fenced, with
the file's language, or `text' when there is no file."
  (when-let* ((quote (alist-get :quote note)))
    (if (eq (alist-get :source note) 'transcript)
        (let ((beg (point)))
          (insert (agent-shell-notes--block-quote quote))
          (agent-shell-notes--fold-quote beg (point) open)
          (insert "\n"))
      (let ((fence (agent-shell-notes--fence quote))
            (file (plist-get (alist-get :location note) :file)))
        (insert fence (if file
                          (agent-shell-notes--fence-language file)
                        "text")
                "\n")
        (let ((beg (point)))
          (insert quote)
          (agent-shell-notes--fold-quote beg (point) open))
        (insert "\n" fence "\n")))))

(defun agent-shell-notes--block-quote (text)
  "Return TEXT with each line trimmed at the end and prefixed by `> '."
  (mapconcat (lambda (line) (concat "> " (string-trim-right line)))
             (split-string text "\n") "\n"))

;;;; Capture popup

(defun agent-shell-notes--face-overlay (beg end face)
  "Give the text from BEG to END the FACE, through an overlay.
Font-lock repaints `face' text properties, so a face that must stay
lives on an overlay.  The overlay goes when its text does."
  (let ((ov (make-overlay beg end nil t)))
    (overlay-put ov 'face face)
    (overlay-put ov 'evaporate t)
    ov))

(defconst agent-shell-notes--capture-buffer-name
  "*agent-shell-notes capture*")

(defcustom agent-shell-notes-capture-display-action
  '(display-buffer-at-bottom (window-height . 0.3))
  "Display action for the capture popup, as for `pop-to-buffer'."
  :type 'sexp)

(defvar-local agent-shell-notes--pending nil
  "The note being written in the capture popup, without id.")

(defvar-local agent-shell-notes--window-configuration nil
  "The window configuration from before the capture popup opened.")

(defvar-keymap agent-shell-notes-capture-mode-map
  :doc "Keymap for `agent-shell-notes-capture-mode'."
  "C-c C-c" #'agent-shell-notes-capture-save
  "C-c C-k" #'agent-shell-notes-capture-abort
  "TAB" #'agent-shell-notes-toggle-quote)

(define-derived-mode agent-shell-notes-capture-mode
  agent-shell-notes--markdown-mode "Note"
  "Major mode of the popup where a note is written.
The location and quote at the top are read-only; the note goes below.
\\<agent-shell-notes-capture-mode-map>\
\\[agent-shell-notes-capture-save] saves, \
\\[agent-shell-notes-capture-abort] aborts, \
\\[agent-shell-notes-toggle-quote] on the quote unfolds it."
  (agent-shell-notes--markdown-setup)
  (add-to-invisibility-spec '(agent-shell-notes-quote . t))
  (setq header-line-format
        (substitute-command-keys
         "\\<agent-shell-notes-capture-mode-map>\
\\[agent-shell-notes-capture-save] save  \
\\[agent-shell-notes-capture-abort] abort  \
\\[agent-shell-notes-toggle-quote] unfold quote")))

;; Set here, not on first use, so reloading after a change of
;; `agent-shell-notes-markdown-mode' moves the map to the new parent.
(set-keymap-parent agent-shell-notes-capture-mode-map
                   (agent-shell-notes--markdown-map))

(declare-function evil-set-initial-state "evil-core" (mode state))

(with-eval-after-load 'evil
  (evil-set-initial-state 'agent-shell-notes-capture-mode 'insert))

(defun agent-shell-notes--capture-insert-header (note)
  "Insert NOTE's read-only location line and quote at point."
  (let ((beg (point)))
    (insert (agent-shell-notes--location-string note))
    (agent-shell-notes--face-overlay beg (point) 'agent-shell-notes-location))
  (insert "\n")
  (agent-shell-notes--insert-quote note)
  (insert "\n")
  (add-text-properties (point-min) (point) '(read-only t front-sticky t))
  (put-text-property (1- (point)) (point) 'rear-nonsticky '(read-only)))

;;;###autoload
(defun agent-shell-notes-capture ()
  "Capture a note from the current buffer.
Copy the region, or the current line, and open a popup for the note.
While a popup is open, switch to it instead."
  (interactive)
  (if-let* ((open (get-buffer agent-shell-notes--capture-buffer-name)))
      (pop-to-buffer open agent-shell-notes-capture-display-action)
    (agent-shell-notes--capture-open)))

(defun agent-shell-notes--capture-open ()
  "Open the capture popup for a note from the current buffer."
  (let ((note (agent-shell-notes--extract))
        (config (current-window-configuration))
        (buffer (get-buffer-create agent-shell-notes--capture-buffer-name)))
    (deactivate-mark)
    (with-current-buffer buffer
      (agent-shell-notes-capture-mode)
      (setq agent-shell-notes--pending note
            agent-shell-notes--window-configuration config)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (agent-shell-notes--capture-insert-header note))
      (setq agent-shell-notes--text-start (point-marker))
      (set-buffer-modified-p nil))
    (pop-to-buffer buffer agent-shell-notes-capture-display-action)))

(defun agent-shell-notes--capture-close ()
  "Kill the capture popup and restore the window configuration."
  (let ((config agent-shell-notes--window-configuration))
    (kill-buffer (current-buffer))
    (when config
      (set-window-configuration config))))

(defun agent-shell-notes-capture-save ()
  "Save the note in the capture popup and close it.
An empty note saves the quote alone."
  (interactive)
  (let ((note (copy-alist agent-shell-notes--pending)))
    (setf (alist-get :text note)
          (string-trim (buffer-substring-no-properties
                        agent-shell-notes--text-start (point-max))))
    (agent-shell-notes--add note)
    (agent-shell-notes--capture-close)
    (agent-shell-notes--review-refresh)))

(defun agent-shell-notes-capture-abort ()
  "Close the capture popup without saving."
  (interactive)
  (agent-shell-notes--capture-close))

;;;; The review

(defconst agent-shell-notes--review-buffer-name "*agent-shell-notes*")

(defcustom agent-shell-notes-review-display-action nil
  "Display action for the review, as for `pop-to-buffer'."
  :type 'sexp)

(defcustom agent-shell-notes-mark-indicator 'fringe
  "How the review shows a marked note.
`fringe' puts a bitmap in the left fringe (a `*' in the left margin
on a text terminal); `background' gives the whole note the face
`agent-shell-notes-mark'."
  :type '(choice (const :tag "Fringe (margin on a tty)" fringe)
                 (const :tag "Background" background)))

(defface agent-shell-notes-archived
  '((t :inherit shadow))
  "Face of an archived note in the review.")

(defface agent-shell-notes-mark
  '((t :inherit region))
  "Face of a marked note's indicator or background.")

(defvar agent-shell-notes--marks nil
  "Ids of the marked notes.
Kept apart from the review buffer, which is redrawn from scratch.")

(defun agent-shell-notes--outside-request (command &optional key)
  "Return a key binding that runs COMMAND except in the request body.
In the body the binding is void, so the key falls through to the next
active map: an evil state map, else the global map (for a printing
key, `self-insert-command').  A void binding skips the parent
Markdown map too, so with KEY the body gets KEY's binding there
instead, if any."
  `(menu-item "" ,command
              :filter ,(lambda (cmd)
                         (cond ((not (agent-shell-notes-in-request-p)) cmd)
                               (key (keymap-lookup (agent-shell-notes--markdown-map)
                                                   key))))))

(defvar-keymap agent-shell-notes-review-mode-map
  :doc "Keymap for `agent-shell-notes-review-mode'.
The printing keys, `RET' and `TAB' are void in the request body, where
they type; see `agent-shell-notes-in-request-p'."
  "n" (agent-shell-notes--outside-request #'agent-shell-notes-next-note)
  "p" (agent-shell-notes--outside-request #'agent-shell-notes-previous-note)
  "m" (agent-shell-notes--outside-request #'agent-shell-notes-mark)
  "u" (agent-shell-notes--outside-request #'agent-shell-notes-unmark)
  "t" (agent-shell-notes--outside-request #'agent-shell-notes-toggle-marks)
  "U" (agent-shell-notes--outside-request #'agent-shell-notes-unmark-all)
  "TAB" (agent-shell-notes--outside-request
         #'agent-shell-notes-toggle-quote "TAB")
  "g" (agent-shell-notes--outside-request #'agent-shell-notes-redraw)
  "k" (agent-shell-notes--outside-request #'agent-shell-notes-delete)
  "D" (agent-shell-notes--outside-request #'agent-shell-notes-delete-marked)
  "x" (agent-shell-notes--outside-request #'agent-shell-notes-purge-archived)
  "e" (agent-shell-notes--outside-request #'agent-shell-notes-edit)
  "C-c C-c" #'agent-shell-notes-send
  "w" (agent-shell-notes--outside-request #'agent-shell-notes-copy)
  "C-c C-r" #'agent-shell-notes-restore-last
  "C-c C-e" #'agent-shell-notes-edit-mode
  "C-x C-q" #'agent-shell-notes-edit-mode
  "RET" (agent-shell-notes--outside-request #'agent-shell-notes-jump "RET")
  "<mouse-1>" #'agent-shell-notes-jump
  "q" (agent-shell-notes--outside-request #'quit-window))

(define-derived-mode agent-shell-notes-review-mode
  agent-shell-notes--markdown-mode "Notes"
  "Major mode of the review, where the collected notes are shown.
The buffer is drawn from the note list; its text is read-only.

\\{agent-shell-notes-review-mode-map}"
  (agent-shell-notes--markdown-setup)
  (add-to-invisibility-spec '(agent-shell-notes-quote . t))
  (setq truncate-lines nil))

(set-keymap-parent agent-shell-notes-review-mode-map
                   (agent-shell-notes--markdown-map))

;;;; Edit mode

(defvar-local agent-shell-notes--edit-slots nil
  "The editable note texts of the review while in edit mode.
Each entry is (ID BEG END): BEG and END delimit the text of note ID.
The review draw records positions; `agent-shell-notes--edit-open-slots'
turns them into markers.")

(defvar-keymap agent-shell-notes-edit-mode-map
  :doc "Local keymap of the review in `agent-shell-notes-edit-mode'.
It replaces `agent-shell-notes-review-mode-map', so the note commands
are inactive and letters insert."
  "C-c C-c" #'agent-shell-notes-edit-commit
  "C-c C-k" #'agent-shell-notes-edit-revert
  "C-c C-e" #'agent-shell-notes-edit-commit
  "C-x C-q" #'agent-shell-notes-edit-commit)

(set-keymap-parent agent-shell-notes-edit-mode-map
                   (agent-shell-notes--markdown-map))

(define-minor-mode agent-shell-notes-edit-mode
  "Edit the note texts of the review, like `wdired-mode'.
Only the note texts are writable; headings, locations and quotes stay
read-only.
\\<agent-shell-notes-edit-mode-map>\
\\[agent-shell-notes-edit-commit] saves the changed texts, \
\\[agent-shell-notes-edit-revert] reverts them."
  :lighter " Edit"
  (unless (derived-mode-p 'agent-shell-notes-review-mode)
    (setq agent-shell-notes-edit-mode nil)
    (user-error "Not in the notes review"))
  (use-local-map (if agent-shell-notes-edit-mode
                     agent-shell-notes-edit-mode-map
                   agent-shell-notes-review-mode-map))
  (agent-shell-notes--review-draw))

(defun agent-shell-notes--edit-open-slots ()
  "Make the recorded note texts writable and track them with markers.
The character before each text stops passing `read-only' on, so text
typed at the start of a note text is writable; the newline after it
stays read-only and ends the text."
  (setq agent-shell-notes--edit-slots
        (mapcar
         (pcase-lambda (`(,id ,beg ,end))
           (remove-list-of-text-properties beg end '(read-only))
           (put-text-property (1- beg) beg 'rear-nonsticky '(read-only))
           (list id (copy-marker beg) (copy-marker end t)))
         agent-shell-notes--edit-slots)))

(defun agent-shell-notes-edit ()
  "Enter edit mode with point at the end of the text of the note at point."
  (interactive)
  (agent-shell-notes--refuse-in-request)
  (let ((id (get-text-property (point) 'agent-shell-notes-id)))
    (unless id
      (user-error "No note at point"))
    (agent-shell-notes-edit-mode 1)
    (goto-char (nth 2 (assq id agent-shell-notes--edit-slots)))))

(defun agent-shell-notes-edit-commit ()
  "Save every note text changed in edit mode and leave edit mode.
An emptied text keeps the note, quote only."
  (interactive)
  (pcase-dolist (`(,id ,beg ,end) agent-shell-notes--edit-slots)
    (when-let* ((note (seq-find (lambda (note) (eql id (alist-get :id note)))
                                agent-shell-notes--notes)))
      (setf (alist-get :text note)
            (string-trim (buffer-substring-no-properties beg end)))))
  (agent-shell-notes-edit-mode -1))

(defun agent-shell-notes-edit-revert ()
  "Drop the changes made in edit mode and leave edit mode."
  (interactive)
  (agent-shell-notes-edit-mode -1))

(defun agent-shell-notes--group-key (note)
  "Return the key of the review group NOTE belongs to."
  (pcase (alist-get :source note)
    ((or 'file 'magit) (cons (agent-shell-notes--note-file note)
                             (alist-get :project note)))
    ('transcript (let ((loc (alist-get :location note)))
                   (list 'transcript
                         (or (plist-get loc :session-id) (plist-get loc :shell))
                         (plist-get loc :turn) (plist-get loc :turn-end)
                         (plist-get loc :kind))))
    ('dired (cons (plist-get (alist-get :location note) :directory)
                  (alist-get :project note)))
    ;; `buffer', and any source added by the user.
    (_ (plist-get (alist-get :location note) :buffer))))

(defun agent-shell-notes--group-heading (note)
  "Return the review heading of the group NOTE belongs to."
  (let ((project (alist-get :project note)))
    (pcase (alist-get :source note)
      ('transcript (concat "# " (agent-shell-notes--location-string note)))
      ((and (or 'file 'magit 'dired) source)
       (format "# %s — %s"
               (file-relative-name
                (if (eq source 'dired)
                    (plist-get (alist-get :location note) :directory)
                  (agent-shell-notes--note-file note))
                project)
               (abbreviate-file-name (directory-file-name project))))
      (_ (format "# %s" (plist-get (alist-get :location note) :buffer))))))

(defun agent-shell-notes--tags (note)
  "Return the review tags of NOTE, a list of strings."
  (let ((loc (alist-get :location note)))
    (delq nil
          (list (pcase (plist-get loc :type)
                  ('staged "staged")
                  ('unstaged "unstaged")
                  ('committed (format "commit %s" (plist-get loc :rev))))
                (and (eq (plist-get loc :side) 'old) "before changes")
                (when-let* ((target (alist-get :archived note)))
                  (format "sent to %s" target))))))

(defun agent-shell-notes--groups ()
  "Return the notes as a list of groups, each a list of notes.
Groups come in the order of their first note's capture; notes in a
group by line."
  (let (keys table)
    (dolist (note agent-shell-notes--notes)
      (let* ((key (agent-shell-notes--group-key note))
             (cell (assoc key table)))
        (if cell
            (push note (cdr cell))
          (push key keys)
          (push (list key note) table))))
    (mapcar (lambda (key)
              (sort (reverse (cdr (assoc key table)))
                    (lambda (a b)
                      (< (or (plist-get (alist-get :location a) :start) 0)
                         (or (plist-get (alist-get :location b) :start) 0)))))
            (nreverse keys))))

(defun agent-shell-notes--insert-field (field text)
  "Insert TEXT marked as review FIELD."
  (insert (propertize text 'agent-shell-notes-field field)))

(defun agent-shell-notes--insert-note (note)
  "Insert NOTE into the review at point."
  (let ((beg (point))
        (id (alist-get :id note))
        (text (alist-get :text note)))
    (agent-shell-notes--insert-field
     'location
     (format "**%s**"
             (pcase (alist-get :source note)
               ('transcript (agent-shell-notes--kind-name
                             (plist-get (alist-get :location note) :kind)))
               ('dired (agent-shell-notes--dired-names
                        note (plist-get (alist-get :location note)
                                        :directory)))
               (_ (agent-shell-notes--range-string
                   (alist-get :location note))))))
    (agent-shell-notes--face-overlay beg (point) 'agent-shell-notes-location)
    (dolist (tag (agent-shell-notes--tags note))
      (agent-shell-notes--insert-field 'location " ")
      (let ((tbeg (point)))
        (agent-shell-notes--insert-field 'location (format "`%s`" tag))
        (agent-shell-notes--face-overlay tbeg (point) 'agent-shell-notes-tag)))
    (insert "\n")
    (agent-shell-notes--insert-quote
     note (memq id agent-shell-notes--unfolded))
    (cond
     (agent-shell-notes-edit-mode
      (let ((tbeg (point)))
        (agent-shell-notes--insert-field 'text text)
        (push (list id tbeg (point)) agent-shell-notes--edit-slots))
      (insert "\n"))
     ((not (string-empty-p text))
      (agent-shell-notes--insert-field 'text text)
      (insert "\n")))
    (put-text-property beg (point) 'agent-shell-notes-id id)
    (when (alist-get :archived note)
      ;; Above the location and tag overlays, so they dim too.
      (overlay-put (agent-shell-notes--face-overlay
                    beg (point) 'agent-shell-notes-archived)
                   'priority 1))
    (when (memq id agent-shell-notes--marks)
      (agent-shell-notes--show-mark id beg (point)))))

(defvar-local agent-shell-notes--request-start nil
  "Marker at the start of the request body in the review.
The body runs from here to the end of the buffer.")

(defun agent-shell-notes-in-request-p ()
  "Return non-nil when point is in the request body of the review.
The review map's printing keys, `RET' and `TAB' test this and are void
in the body, so they type there.  Use it as a `menu-item' `:filter'
to make your own review bindings do the same, for example:

  (keymap-set agent-shell-notes-review-mode-map \"j\"
              \\=`(menu-item \"\" agent-shell-notes-next-note
                          :filter ,(lambda (cmd)
                                     (unless (agent-shell-notes-in-request-p)
                                       cmd))))"
  (and agent-shell-notes--request-start
       (>= (point) agent-shell-notes--request-start)))

(defun agent-shell-notes--refuse-in-request ()
  "Signal `user-error' when point is in the request body of the review.
Note commands call this first: the body holds no note."
  (when (agent-shell-notes-in-request-p)
    (user-error "Point is in the request")))

(defun agent-shell-notes--request-text ()
  "Return the request body of the review, or \"\" when there is none."
  (if-let* ((buffer (get-buffer agent-shell-notes--review-buffer-name))
            (start (buffer-local-value 'agent-shell-notes--request-start
                                       buffer)))
      (with-current-buffer buffer
        (buffer-substring-no-properties start (point-max)))
    ""))

(defun agent-shell-notes--insert-request (request)
  "Insert the read-only request heading, then the writable REQUEST body.
The newline before the body passes the body's properties on but not
`read-only', so text typed into an empty body is writable."
  (insert (propertize "# Request\n\n" 'read-only t))
  (add-text-properties (1- (point)) (point)
                       '(rear-nonsticky (read-only)
                         agent-shell-notes-field request))
  (setq agent-shell-notes--request-start (point-marker))
  (insert (propertize request 'agent-shell-notes-field 'request)))

(defun agent-shell-notes--review-draw ()
  "Redraw the current review buffer from the note list.
Point stays on the note it was on.  The request body is kept."
  (let ((id (get-text-property (point) 'agent-shell-notes-id))
        (pos (point))
        (request (agent-shell-notes--request-text))
        (inhibit-read-only t))
    (remove-overlays)
    (erase-buffer)
    (setq agent-shell-notes--edit-slots nil)
    (dolist (group (agent-shell-notes--groups))
      (let ((first (car group)))
        (insert (propertize (agent-shell-notes--group-heading first)
                            'agent-shell-notes-group
                            (agent-shell-notes--group-key first))
                "\n\n"))
      (dolist (note group)
        (agent-shell-notes--insert-note note)
        (insert "\n")))
    (add-text-properties (point-min) (point-max) '(read-only t))
    ;; Nothing before the first character passes `read-only' on.
    (put-text-property (point-min) (min (1+ (point-min)) (point-max))
                       'front-sticky '(read-only))
    (agent-shell-notes--edit-open-slots)
    (goto-char (point-max))
    (agent-shell-notes--insert-request request)
    (goto-char (or (and id (text-property-any (point-min) (point-max)
                                              'agent-shell-notes-id id))
                   (min pos (point-max))))
    (set-buffer-modified-p nil)))

(defun agent-shell-notes--review-refresh ()
  "Redraw the review buffer, if live.
Every window showing it stays on the note it showed."
  (when-let* ((buffer (get-buffer agent-shell-notes--review-buffer-name))
              ((not (buffer-local-value 'agent-shell-notes-edit-mode buffer))))
    (let ((windows (mapcar (lambda (window)
                             (cons window (get-text-property
                                           (window-point window)
                                           'agent-shell-notes-id buffer)))
                           (get-buffer-window-list buffer nil t))))
      (with-current-buffer buffer
        (agent-shell-notes--review-draw)
        (pcase-dolist (`(,window . ,id) windows)
          (when-let* ((pos (and id (text-property-any
                                    (point-min) (point-max)
                                    'agent-shell-notes-id id))))
            (set-window-point window pos)))))))

(defun agent-shell-notes--note-start (pos)
  "Return the start of the review note at POS."
  (if (or (= pos (point-min))
          (not (eq (get-text-property pos 'agent-shell-notes-id)
                   (get-text-property (1- pos) 'agent-shell-notes-id))))
      pos
    (previous-single-property-change pos 'agent-shell-notes-id)))

(defun agent-shell-notes-next-note ()
  "Move to the start of the next note."
  (interactive)
  (agent-shell-notes--refuse-in-request)
  (let ((pos (point)))
    (while (and (setq pos (next-single-property-change
                           pos 'agent-shell-notes-id))
                (not (get-text-property pos 'agent-shell-notes-id))))
    (unless pos
      (user-error "No next note"))
    (goto-char pos)))

(defun agent-shell-notes-previous-note ()
  "Move to the start of the previous note."
  (interactive)
  (agent-shell-notes--refuse-in-request)
  (let ((pos (agent-shell-notes--note-start (point))))
    (while (and (setq pos (previous-single-property-change
                           pos 'agent-shell-notes-id))
                (not (get-text-property pos 'agent-shell-notes-id))))
    (unless pos
      (user-error "No previous note"))
    (goto-char pos)))

;;;; Marks

(defun agent-shell-notes--show-mark (id beg end)
  "Draw the mark indicator of note ID, which spans BEG to END."
  (let ((ov (make-overlay beg end nil t)))
    (overlay-put ov 'agent-shell-notes-mark id)
    (overlay-put ov 'evaporate t)
    (cond
     ((eq agent-shell-notes-mark-indicator 'background)
      (overlay-put ov 'face 'agent-shell-notes-mark))
     ((display-graphic-p)
      (overlay-put ov 'before-string
                   (propertize "*" 'display '(left-fringe
                                              filled-rectangle
                                              agent-shell-notes-mark))))
     (t
      (setq left-margin-width 1)
      (dolist (window (get-buffer-window-list nil nil t))
        (set-window-margins window 1 (cdr (window-margins window))))
      (overlay-put ov 'before-string
                   (propertize "*" 'display
                               `((margin left-margin)
                                 ,(propertize "*" 'face
                                              'agent-shell-notes-mark))))))))

(defun agent-shell-notes--note-end (pos)
  "Return the end of the review note at POS."
  (or (next-single-property-change pos 'agent-shell-notes-id)
      (point-max)))

(defun agent-shell-notes--apply-marks ()
  "Redraw the mark indicators of the current review buffer."
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (overlay-get ov 'agent-shell-notes-mark)
      (delete-overlay ov)))
  (let ((pos (point-min)))
    (while (setq pos (text-property-not-all pos (point-max)
                                            'agent-shell-notes-id nil))
      (let ((id (get-text-property pos 'agent-shell-notes-id))
            (end (agent-shell-notes--note-end pos)))
        (when (memq id agent-shell-notes--marks)
          (agent-shell-notes--show-mark id pos end))
        (setq pos end)))))

(defun agent-shell-notes--set-marks (marked)
  "Set the marks of every note to MARKED, then show them."
  (setq agent-shell-notes--marks marked)
  (when-let* ((buffer (get-buffer agent-shell-notes--review-buffer-name)))
    (with-current-buffer buffer
      (agent-shell-notes--apply-marks))))

(defun agent-shell-notes--ids-at-point ()
  "Return the ids of the notes the region touches, else the note at point.
Signal `user-error' when there is none."
  (let ((ids
         (if (use-region-p)
             (let ((pos (region-beginning))
                   (end (region-end))
                   ids)
               (while (< pos end)
                 (when-let* ((id (get-text-property
                                  pos 'agent-shell-notes-id)))
                   (push id ids))
                 (setq pos (next-single-property-change
                            pos 'agent-shell-notes-id nil end)))
               (nreverse ids))
           (when-let* ((id (get-text-property (point) 'agent-shell-notes-id)))
             (list id)))))
    (or ids (user-error "No note at point"))))

(defun agent-shell-notes--mark-at-point (mark)
  "Mark the notes at point when MARK is non-nil, else unmark them.
Then move to the note after the last one, if any."
  (agent-shell-notes--refuse-in-request)
  (let* ((ids (agent-shell-notes--ids-at-point))
         (last (car (last ids))))
    (deactivate-mark)
    (agent-shell-notes--set-marks
     (if mark
         (seq-union agent-shell-notes--marks ids)
       (seq-difference agent-shell-notes--marks ids)))
    (goto-char (agent-shell-notes--note-start
                (text-property-any (point-min) (point-max)
                                   'agent-shell-notes-id last)))
    (ignore-errors (agent-shell-notes-next-note))))

(defun agent-shell-notes-mark ()
  "Mark the note at point, or every note the region touches.
Then move to the next note."
  (interactive)
  (agent-shell-notes--mark-at-point t))

(defun agent-shell-notes-unmark ()
  "Unmark the note at point, or every note the region touches.
Then move to the next note."
  (interactive)
  (agent-shell-notes--mark-at-point nil))

(defun agent-shell-notes-toggle-marks ()
  "Invert the mark of every note that is not archived.
With no note marked, this marks them all."
  (interactive)
  (agent-shell-notes--set-marks
   (delq nil
         (mapcar (lambda (note)
                   (let* ((id (alist-get :id note))
                          (marked (memq id agent-shell-notes--marks)))
                     (when (if (alist-get :archived note) marked (not marked))
                       id)))
                 agent-shell-notes--notes))))

(defun agent-shell-notes-unmark-all ()
  "Unmark every note."
  (interactive)
  (agent-shell-notes--set-marks nil))

(defun agent-shell-notes-delete ()
  "Delete the note at point, without confirmation."
  (interactive)
  (agent-shell-notes--refuse-in-request)
  (let ((id (get-text-property (point) 'agent-shell-notes-id)))
    (unless id
      (user-error "No note at point"))
    (setq agent-shell-notes--notes
          (seq-remove (lambda (note) (eql id (alist-get :id note)))
                      agent-shell-notes--notes)
          agent-shell-notes--unfolded (delq id agent-shell-notes--unfolded)
          agent-shell-notes--marks (delq id agent-shell-notes--marks))
    (agent-shell-notes--review-draw)))

;;;; Jump

(defun agent-shell-notes--jump-target ()
  "Return the note whose source `agent-shell-notes-jump' shows, or nil.
The note of the location line at point, or the first note of the
group whose heading is at point."
  (let ((bol (line-beginning-position)))
    (when-let* ((id (cond
                     ((eq 'location (get-text-property
                                     bol 'agent-shell-notes-field))
                      (get-text-property bol 'agent-shell-notes-id))
                     ((get-text-property bol 'agent-shell-notes-group)
                      (when-let* ((pos (next-single-property-change
                                        bol 'agent-shell-notes-id)))
                        (get-text-property pos 'agent-shell-notes-id))))))
      (seq-find (lambda (note) (eql id (alist-get :id note)))
                agent-shell-notes--notes))))

(defun agent-shell-notes--jump-show (buffer beg end)
  "Show BUFFER with point at BEG and flash BEG..END."
  (pop-to-buffer buffer)
  (goto-char beg)
  (pulse-momentary-highlight-region beg end))

(defun agent-shell-notes--jump-file (note)
  "Visit the file of NOTE and flash its line range."
  (let* ((loc (alist-get :location note))
         (buffer (find-file-noselect (agent-shell-notes--note-file note)))
         beg end)
    (with-current-buffer buffer
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (forward-line (1- (plist-get loc :start)))
          (setq beg (point))
          (forward-line (- (plist-get loc :end) (plist-get loc :start)))
          (setq end (line-end-position)))))
    (agent-shell-notes--jump-show buffer beg end)))

(defun agent-shell-notes--jump-viewport (note shell)
  "Reopen SHELL's viewport on NOTE's turn page and flash the quote.
A turn the shell no longer has, or none, shows the latest page.  The
markers died with the old viewport, so the quote is searched for
with `agent-shell-notes--find-quote'; not found, point stays at the
page start and nothing flashes.  A compose draft in a viewport opened since
is parked, as paging parks it."
  (let* ((turns (length (with-current-buffer shell (agent-shell--turns))))
         (turn (plist-get (alist-get :location note) :turn))
         (viewport (agent-shell-viewport--buffer :shell-buffer shell))
         range)
    (with-current-buffer viewport
      ;; Paging erases the buffer; park a compose draft as
      ;; `agent-shell-viewport-view-last' does.
      (when (and (derived-mode-p 'agent-shell-viewport-edit-mode)
                 (not (string-blank-p (buffer-string))))
        (setq agent-shell-viewport--compose-snapshot
              `((:content . ,(buffer-string)) (:location . ,(point)))))
      (agent-shell-viewport-view-mode)
      (if (zerop turns)
          (agent-shell-viewport--initialize)
        (agent-shell-viewport--show-page
         (if (and turn (<= 1 turn turns)) turn turns)))
      (setq range (agent-shell-notes--find-quote
                   (alist-get :quote note))))
    (if range
        (agent-shell-notes--jump-show viewport (car range) (cdr range))
      (pop-to-buffer viewport)
      (goto-char (point-min)))))

(defun agent-shell-notes--page-markdown ()
  "Return the current buffer as Markdown, with a way back to positions.
A list (MARKDOWN STARTS ENDS).  A rendered span stands for its
`agent-shell-markdown-source', as `agent-shell-markdown-reconstruct'
gives it for a whole page; STARTS and ENDS are vectors holding the
buffer start and end of the text each MARKDOWN char came from."
  (let ((pos (point-min)) parts starts ends)
    (while (< pos (point-max))
      (let* ((source (get-text-property pos 'agent-shell-markdown-source))
             (next (next-single-property-change
                    pos 'agent-shell-markdown-source nil (point-max)))
             (text (or source (buffer-substring-no-properties pos next))))
        (push text parts)
        (dotimes (i (length text))
          (push (if source pos (+ pos i)) starts)
          (push (if source next (+ pos i 1)) ends))
        (setq pos next)))
    (list (apply #'concat (nreverse parts))
          (vconcat (nreverse starts))
          (vconcat (nreverse ends)))))

(defun agent-shell-notes--find-quote (quote)
  "Return (BEG . END) of QUOTE in the current buffer, or nil.
QUOTE is Markdown, so it is looked for in the page's Markdown, then
in its visible text (a quote that began inside a rendered span holds
visible text); the whole QUOTE first, then each of its lines."
  (let ((views (list (agent-shell-notes--page-markdown)
                     (list (buffer-substring-no-properties
                            (point-min) (point-max))))))
    (seq-some
     (lambda (needle)
       (seq-some
        (pcase-lambda (`(,text ,starts ,ends))
          (when-let* ((beg (string-search needle text)))
            (let ((last (+ beg (length needle) -1)))
              (if starts
                  (cons (aref starts beg) (aref ends last))
                (cons (+ (point-min) beg) (+ (point-min) last 1))))))
        views))
     (seq-remove #'string-blank-p
                 (cons (or quote "")
                       (mapcar #'string-trim
                               (split-string (or quote "") "\n")))))))

(defun agent-shell-notes--jump-dead (note)
  "Show the source of NOTE, whose source buffer is gone."
  (let ((loc (alist-get :location note)))
    (pcase (alist-get :source note)
      ('file (agent-shell-notes--jump-file note))
      ('magit
       (cond
        ((eq 'old (plist-get loc :side))
         (user-error "Source buffer is gone; the old side has no file"))
        ((eq 'committed (plist-get loc :type))
         (user-error "Source buffer is gone; the note is on a commit"))
        (t (agent-shell-notes--jump-file note))))
      ('dired
       (pop-to-buffer (dired-noselect (plist-get loc :directory)))
       (dired-goto-file (car (plist-get loc :files))))
      ;; A dead source with a live shell was a viewport: had the shell
      ;; been the source, the live path would have shown it.  The shell
      ;; is the one on the note's session, whatever its name now.
      ('transcript
       (if-let* ((session (plist-get loc :session-id))
                 (shell (seq-find
                         (lambda (shell)
                           (equal session (agent-shell-session-id
                                           :shell-buffer shell)))
                         (agent-shell-buffers))))
           (agent-shell-notes--jump-viewport note shell)
         (user-error "Source buffer is gone")))
      ;; `buffer', and any source added by the user.
      (_ (user-error "Source buffer is gone")))))

(defun agent-shell-notes-jump (&optional event)
  "Show the source of the note at point and flash the quoted range.
On a location line, the note's source; on a group heading, the
source of the group's first note.  Bound to a mouse click, EVENT,
first move point to the click; a click elsewhere only moves point."
  (interactive (list last-nonmenu-event))
  (let ((click (mouse-event-p event)))
    (when click
      (mouse-set-point event))
    (when-let* ((note (or (agent-shell-notes--jump-target)
                          (unless click
                            (user-error "No note source at point")))))
      (agent-shell-notes--jump-note note))))

(defun agent-shell-notes--jump-note (note)
  "Show the source of NOTE and flash its range."
  (pcase-let ((`(,buffer ,beg ,end) (alist-get :markers note)))
    (if (and (buffer-live-p buffer) (markerp beg)
             (eq buffer (marker-buffer beg)))
        (agent-shell-notes--jump-show buffer beg end)
      (agent-shell-notes--jump-dead note))))

;;;; Send and copy

(defcustom agent-shell-notes-agent-shell-disposition nil
  "How the agent-shell client sends to a busy shell.
nil leaves it to `agent-shell-busy-submit-default-function'; `queue'
queues the prompt; `steer' steers the running turn."
  :type '(choice (const :tag "agent-shell default" nil)
                 (const :tag "Queue" queue)
                 (const :tag "Steer" steer)))

(defun agent-shell-notes--agent-shell-project (shell)
  "Return the project directory of SHELL."
  (buffer-local-value 'default-directory shell))

(defun agent-shell-notes--agent-shell-sort (shells hint)
  "Return SHELLS ordered for the picker by HINT.
The last target first, then shells in one of HINT's projects, then the
rest; within each band SHELLS keep their order."
  (let ((last (plist-get hint :last))
        (projects (mapcar #'agent-shell-notes--directory
                          (plist-get hint :projects))))
    (seq-sort-by (lambda (shell)
                   (cond ((eq shell last) 0)
                         ((member (agent-shell-notes--directory
                                   (agent-shell-notes--agent-shell-project
                                    shell))
                                  projects)
                          1)
                         (t 2)))
                 #'< shells)))

(defun agent-shell-notes--agent-shell-read-session (hint)
  "Pick a live shell, ordered by HINT, and return its buffer.
HINT is a plist (:projects LIST :last SESSION)."
  (let ((shells (agent-shell-buffers)))
    (unless shells
      (user-error "No agent-shell session"))
    (agent-shell--read-shell-buffer
     :prompt "Send notes to: "
     :buffers (agent-shell-notes--agent-shell-sort shells hint))))

(defun agent-shell-notes--agent-shell-send (shell text)
  "Send TEXT to SHELL as one prompt.
Refuse a shell whose agent has no session yet: agent-shell would hold
the prompt until the agent starts and still return normally."
  (unless (buffer-live-p shell)
    (user-error "The agent-shell session is gone"))
  (unless (agent-shell-session-id :shell-buffer shell)
    (user-error "Starting agent, please wait"))
  (with-current-buffer shell
    (agent-shell--prompt-send
     :prompt text
     :disposition agent-shell-notes-agent-shell-disposition)))

(defun agent-shell-notes--agent-shell-compose (shell text)
  "Append TEXT to SHELL's viewport compose buffer and switch there.
The text goes after any draft, and the draft's queue/steer choice is
kept: reading it back must not create a viewport, and
`agent-shell-viewport--show-buffer' always writes the disposition."
  (unless (buffer-live-p shell)
    (user-error "The agent-shell session is gone"))
  (let ((disposition
         (when-let* ((viewport (agent-shell-viewport--buffer
                                :shell-buffer shell :existing-only t)))
           (buffer-local-value 'agent-shell-viewport--compose-disposition
                               viewport))))
    (agent-shell-viewport--show-buffer :append text :shell-buffer shell
                                       :edit t :disposition disposition)))

(defun agent-shell-notes--agent-shell-session-id (shell)
  "Return the ACP session id of SHELL."
  (agent-shell-session-id :shell-buffer shell))

(defun agent-shell-notes--agent-shell-turn-count (shell)
  "Return the number of turns in SHELL."
  (with-current-buffer shell
    (length (agent-shell--turns))))

(defconst agent-shell-notes-agent-shell-client
  (list :read-session #'agent-shell-notes--agent-shell-read-session
        :send #'agent-shell-notes--agent-shell-send
        :compose #'agent-shell-notes--agent-shell-compose
        :name #'buffer-name
        :project #'agent-shell-notes--agent-shell-project
        :session-id #'agent-shell-notes--agent-shell-session-id
        :turn-count #'agent-shell-notes--agent-shell-turn-count)
  "The agent-shell client; a session is a shell buffer.")

(defcustom agent-shell-notes-client agent-shell-notes-agent-shell-client
  "The client notes are sent to, a plist of functions:

  :read-session (HINT) -> SESSION   pick a target; HINT is
                                    (:projects LIST :last SESSION)
  :send (SESSION TEXT)              send TEXT; returning normally
                                    means sent
  :compose (SESSION TEXT)           optional; put TEXT in the session's
                                    compose buffer for a final edit
  :name (SESSION) -> string         the session's name
  :project (SESSION) -> directory   the session's project
  :session-id (SESSION) -> string   the session's id
  :turn-count (SESSION) -> integer  the number of turns so far"
  :type '(plist :value-type function))

(defvar agent-shell-notes--last-target nil
  "The session of the last successful send.")

;;;; After send

(defcustom agent-shell-notes-after-send 'remove
  "What a send or compose does to the notes that went out.
`remove' takes them off the list; `archive' keeps them in place,
dimmed and tagged with the target's name; `keep' leaves them.  Marks
and the request clear after every send in every mode."
  :type '(choice (const :tag "Remove" remove)
                 (const :tag "Archive" archive)
                 (const :tag "Keep" keep)))

(defun agent-shell-notes--set-request (text)
  "Replace the request body of the review, if live, with TEXT."
  (when-let* ((buffer (get-buffer agent-shell-notes--review-buffer-name))
              (start (buffer-local-value 'agent-shell-notes--request-start
                                         buffer)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (save-excursion
          (delete-region start (point-max))
          (goto-char start)
          (insert-and-inherit text))))))

;;;###autoload
(defun agent-shell-notes-set-after-send (mode)
  "Set `agent-shell-notes-after-send' to MODE for this Emacs session."
  (interactive
   (list (intern (completing-read
                  (format "After send (now %s): "
                          agent-shell-notes-after-send)
                  '("remove" "archive" "keep") nil t))))
  (setq agent-shell-notes-after-send mode)
  (message "After send: %s" mode))

(defun agent-shell-notes--set-archived (note value)
  "Set NOTE's `:archived' to VALUE, in place."
  (if-let* ((cell (assq :archived note)))
      (setcdr cell value)
    (nconc note (list (cons :archived value)))))

(defvar agent-shell-notes--last-send nil
  "What `agent-shell-notes-restore-last' puts back, or nil.
A plist: `:mode' the after-send mode applied, `:marks', `:request',
and `:notes', a list of (NOTE INDEX ARCHIVED) with each sent note,
its index in the note list and its `:archived' before the send.")

(defun agent-shell-notes--after-send (notes session)
  "Apply `agent-shell-notes-after-send' to NOTES, just sent to SESSION.
Then clear the marks and the request and redraw the review.  Keep
what `agent-shell-notes-restore-last' needs to undo this."
  (setq agent-shell-notes--last-send
        (list :mode agent-shell-notes-after-send
              :marks agent-shell-notes--marks
              :request (agent-shell-notes--request-text)
              :notes (mapcar (lambda (note)
                               (list note
                                     (seq-position agent-shell-notes--notes
                                                   note #'eq)
                                     (alist-get :archived note)))
                             notes)))
  (pcase agent-shell-notes-after-send
    ('remove
     (setq agent-shell-notes--notes
           (seq-remove (lambda (note) (memq note notes))
                       agent-shell-notes--notes)))
    ('archive
     (let ((name (funcall (plist-get agent-shell-notes-client :name) session)))
       (dolist (note notes)
         (agent-shell-notes--set-archived note name)))))
  (setq agent-shell-notes--marks nil)
  (agent-shell-notes--set-request "")
  (agent-shell-notes--review-refresh))

(defun agent-shell-notes--selected-notes ()
  "Return the marked notes in review order, else the note at point.
Marks of deleted notes are ignored.  Signal `user-error' when there is
nothing to send."
  (let* ((notes (apply #'append (agent-shell-notes--groups)))
         (marked (seq-filter (lambda (note)
                               (memq (alist-get :id note)
                                     agent-shell-notes--marks))
                             notes))
         (id (get-text-property (point) 'agent-shell-notes-id)))
    (or marked
        (and id (seq-filter (lambda (note) (eql id (alist-get :id note)))
                            notes))
        (user-error "No note at point"))))

(defun agent-shell-notes-send (&optional compose)
  "Send the marked notes, else the note at point, and the request.
Pick a target session, render the notes in `agent-shell-notes-style'
and send them as one prompt.  With prefix argument COMPOSE, put the
prompt in the target's compose buffer instead, to edit before sending."
  (interactive "P")
  (agent-shell-notes--send-notes (agent-shell-notes--selected-notes) compose))

;;;###autoload
(defun agent-shell-notes-send-all (&optional compose)
  "Send every note that is not archived, and the request.
As `agent-shell-notes-send' with every note marked, without opening
the review; marks are ignored.  With prefix argument COMPOSE, put the
prompt in the target's compose buffer instead."
  (interactive "P")
  (agent-shell-notes--send-notes
   (or (seq-remove (lambda (note) (alist-get :archived note))
                   (apply #'append (agent-shell-notes--groups)))
       (user-error "No unarchived notes"))
   compose))

(defun agent-shell-notes--send-notes (notes compose)
  "Send NOTES and the request to a picked session, then apply after-send.
With COMPOSE, fill the session's compose buffer instead."
  (let* ((client agent-shell-notes-client)
         (_ (when (and compose (not (plist-get client :compose)))
              (user-error "Client %S cannot fill a compose buffer" client)))
         (session (funcall (plist-get client :read-session)
                           (list :projects
                                 (delete-dups
                                  (mapcar (lambda (note)
                                            (alist-get :project note))
                                          notes))
                                 :last agent-shell-notes--last-target)))
         (text (agent-shell-notes--render
                notes (agent-shell-notes--request-text)
                (funcall (plist-get client :project) session)
                (funcall (plist-get client :session-id) session)
                (funcall (plist-get client :turn-count) session))))
    ;; Compose selects the compose buffer's window; what follows still
    ;; acts on the review.
    (save-current-buffer
      (funcall (plist-get client (if compose :compose :send)) session text))
    (agent-shell-notes--after-send notes session)
    (setq agent-shell-notes--last-target session)
    (message "%s %d notes to %s" (if compose "Composed" "Sent") (length notes)
             (funcall (plist-get client :name) session))))

(defun agent-shell-notes-copy ()
  "Copy the text a send of the same notes would send.
Paths are relative, as there is no target.  Nothing else changes."
  (interactive)
  (let ((notes (agent-shell-notes--selected-notes)))
    (kill-new (agent-shell-notes--render
               notes (agent-shell-notes--request-text) nil))
    (message "Copied %d notes" (length notes))))

(defun agent-shell-notes-delete-marked ()
  "Delete the marked notes, after confirmation."
  (interactive)
  (let ((ids (seq-filter (lambda (id) (memq id agent-shell-notes--marks))
                         (mapcar (lambda (note) (alist-get :id note))
                                 agent-shell-notes--notes))))
    (unless ids
      (user-error "No marked notes"))
    (when (yes-or-no-p (format "Delete %d marked note%s? "
                               (length ids) (if (cdr ids) "s" "")))
      (setq agent-shell-notes--notes
            (seq-remove (lambda (note) (memq (alist-get :id note) ids))
                        agent-shell-notes--notes)
            agent-shell-notes--unfolded
            (seq-difference agent-shell-notes--unfolded ids)
            agent-shell-notes--marks nil)
      (agent-shell-notes--review-draw))))

;;;###autoload
(defun agent-shell-notes-restore-last ()
  "Undo the review side of the last send or compose.
Removed notes return to their places, archived notes get their old
tags back, and the marks and request return.  Nothing is unsent."
  (interactive)
  (let ((last agent-shell-notes--last-send))
    (unless last
      (user-error "Nothing to restore"))
    (pcase (plist-get last :mode)
      ('remove
       (let ((entries (sort (copy-sequence (plist-get last :notes))
                            (lambda (a b) (< (nth 1 a) (nth 1 b))))))
         (pcase-dolist (`(,note ,index ,_) entries)
           (unless (memq note agent-shell-notes--notes)
             (let ((index (min index (length agent-shell-notes--notes))))
               (setq agent-shell-notes--notes
                     (append (seq-take agent-shell-notes--notes index)
                             (list note)
                             (seq-drop agent-shell-notes--notes index))))))))
      ('archive
       (pcase-dolist (`(,note ,_ ,archived) (plist-get last :notes))
         (agent-shell-notes--set-archived note archived))))
    (setq agent-shell-notes--last-send nil
          agent-shell-notes--marks (plist-get last :marks))
    (agent-shell-notes--set-request (plist-get last :request))
    (agent-shell-notes--review-refresh)
    (message "Restored %d notes" (length (plist-get last :notes)))))

(defun agent-shell-notes-purge-archived ()
  "Delete every archived note, without confirmation."
  (interactive)
  (let ((ids (mapcar (lambda (note) (alist-get :id note))
                     (seq-filter (lambda (note) (alist-get :archived note))
                                 agent-shell-notes--notes))))
    (setq agent-shell-notes--notes
          (seq-remove (lambda (note) (memq (alist-get :id note) ids))
                      agent-shell-notes--notes)
          agent-shell-notes--unfolded
          (seq-difference agent-shell-notes--unfolded ids)
          agent-shell-notes--marks
          (seq-difference agent-shell-notes--marks ids))
    (agent-shell-notes--review-draw)
    (message "Purged %d archived note%s" (length ids)
             (if (= 1 (length ids)) "" "s"))))

(defun agent-shell-notes-redraw ()
  "Redraw the review from the note list."
  (interactive)
  (agent-shell-notes--review-draw))

;;;###autoload
(defun agent-shell-notes-review ()
  "Show the review of every collected note."
  (interactive)
  (let ((buffer (get-buffer agent-shell-notes--review-buffer-name)))
    (unless buffer
      (setq buffer (get-buffer-create agent-shell-notes--review-buffer-name))
      (with-current-buffer buffer
        (agent-shell-notes-review-mode)
        (agent-shell-notes--review-draw)
        (goto-char (point-min))))
    (pop-to-buffer buffer agent-shell-notes-review-display-action)))

(provide 'agent-shell-notes)
;;; agent-shell-notes.el ends here
