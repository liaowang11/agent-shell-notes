;;; agent-shell-notes.el --- Collect review notes and send them to agent-shell -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; Copyright (C) 2026 Bill and contributors

;; Author: Bill
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell) (markdown-mode))
;; Keywords: convenience, tools
;; URL: https://github.com/liaowang11/agent-shell-notes

;;; Commentary:

;; Select text in a Magit diff, a file, a dired listing, an agent-shell
;; transcript or any other buffer, write a remark, and keep going.  The
;; remarks collect in one global review.  From the review, mark some or all,
;; pick a live agent-shell session, and send them as one prompt rendered in
;; the wire format of a chosen agent app.
;;
;; Magit is optional: the Magit source is skipped when Magit is not loaded.

;;; Code:

(require 'agent-shell)
(require 'markdown-mode)
(require 'project)
(require 'dired)

(defgroup agent-shell-notes nil
  "Collect review notes and send them to agent-shell."
  :group 'tools
  :prefix "agent-shell-notes-")

(defface agent-shell-notes-location
  '((t :inherit font-lock-comment-face))
  "Face of a note's location line.")

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

(defun agent-shell-notes--dired-p ()
  "Return non-nil in a dired buffer."
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
  '((dired agent-shell-notes--dired-p agent-shell-notes--dired-extract)
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

(defun agent-shell-notes--range-string (location)
  "Return \"line N\" or \"lines S-E\" for LOCATION."
  (let ((start (plist-get location :start))
        (end (plist-get location :end)))
    (if (eql start end)
        (format "line %d" start)
      (format "lines %d-%d" start end))))

(defun agent-shell-notes--dired-names (note &optional dir)
  "Return the files of dired NOTE, comma-joined.
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
  :type '(choice (const :tag "Claude desktop" claude)))

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
     (agent-shell-notes--claude-mentions
      (mapconcat #'string-trim-right (split-string quote "\n") "\n"))
     t t)))

(defun agent-shell-notes--note-path (note project &optional file)
  "Return the path of NOTE's file as sent to a target in PROJECT.
Relative to the note's project, or absolute when PROJECT, if non-nil,
is another project.  FILE, if non-nil, is the file instead of the
note's `:file'."
  (let ((file (or file (plist-get (alist-get :location note) :file)))
        (own (alist-get :project note)))
    (if (and project
             (not (equal (file-name-as-directory (expand-file-name project))
                         (file-name-as-directory (expand-file-name own)))))
        file
      (file-relative-name file own))))

(defun agent-shell-notes--claude-file-block (note project)
  "Return the Claude block of file NOTE for a target in PROJECT."
  (let* ((loc (alist-get :location note))
         (quote (alist-get :quote note))
         (text (alist-get :text note))
         (lines (list (format "In `%s` at %s:"
                              (agent-shell-notes--claude-path
                               (agent-shell-notes--note-path note project))
                              (agent-shell-notes--range-string loc)))))
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

(defun agent-shell-notes--claude-dired-block (note project)
  "Return the Claude block of dired NOTE for a target in PROJECT."
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
    ('file (agent-shell-notes--claude-file-block note project))
    ('dired (agent-shell-notes--claude-dired-block note project))
    ;; `buffer', and any source added by the user.
    (_ (agent-shell-notes--claude-buffer-block note))))

(defun agent-shell-notes--render (notes request project)
  "Return NOTES and REQUEST rendered in `agent-shell-notes-style'.
NOTES are in review order.  PROJECT is the target's project, or nil
when there is no target; a note from another project gets an absolute
path."
  (let ((blocks (mapconcat (lambda (note)
                             (agent-shell-notes--claude-block note project))
                           notes "\n\n"))
        (request (string-trim request)))
    (cond ((string-empty-p request) blocks)
          ((string-empty-p blocks) request)
          (t (concat blocks "\n\n\n" request)))))

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
      (call-interactively (lookup-key markdown-mode-map (kbd "TAB")))))))

;;;; Capture popup

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

(define-derived-mode agent-shell-notes-capture-mode markdown-mode "Note"
  "Major mode of the popup where a note is written.
The location and quote at the top are read-only; the note goes below.
\\<agent-shell-notes-capture-mode-map>\
\\[agent-shell-notes-capture-save] saves, \
\\[agent-shell-notes-capture-abort] aborts, \
\\[agent-shell-notes-toggle-quote] on the quote unfolds it."
  (add-to-invisibility-spec '(agent-shell-notes-quote . t))
  (setq header-line-format
        (substitute-command-keys
         "\\<agent-shell-notes-capture-mode-map>\
\\[agent-shell-notes-capture-save] save  \
\\[agent-shell-notes-capture-abort] abort  \
\\[agent-shell-notes-toggle-quote] unfold quote")))

(declare-function evil-set-initial-state "evil-core" (mode state))

(with-eval-after-load 'evil
  (evil-set-initial-state 'agent-shell-notes-capture-mode 'insert))

(defun agent-shell-notes--capture-insert-header (note)
  "Insert NOTE's read-only location line and quote at point."
  (let ((quote (alist-get :quote note))
        (loc (alist-get :location note)))
    (insert (propertize
             (pcase (alist-get :source note)
               ('file (concat (file-relative-name (plist-get loc :file)
                                                  (alist-get :project note))
                              " " (agent-shell-notes--range-string loc)))
               ('dired (agent-shell-notes--dired-names note))
               (_ (format "%s (%s) %s" (plist-get loc :buffer)
                          (plist-get loc :mode)
                          (agent-shell-notes--range-string loc))))
             'face 'agent-shell-notes-location)
            "\n")
    (when quote
      (let ((fence (agent-shell-notes--fence quote)))
        (insert fence "\n")
        (let ((beg (point)))
          (insert quote)
          (agent-shell-notes--fold-quote beg (point)))
        (insert "\n" fence "\n")))
    (insert "\n")
    (add-text-properties (point-min) (point) '(read-only t front-sticky t))
    (put-text-property (1- (point)) (point) 'rear-nonsticky '(read-only))))

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

(defvar-keymap agent-shell-notes-review-mode-map
  :doc "Keymap for `agent-shell-notes-review-mode'."
  "n" #'agent-shell-notes-next-note
  "p" #'agent-shell-notes-previous-note
  "m" #'agent-shell-notes-mark
  "u" #'agent-shell-notes-unmark
  "t" #'agent-shell-notes-toggle-marks
  "U" #'agent-shell-notes-unmark-all
  "TAB" #'agent-shell-notes-toggle-quote
  "g" #'agent-shell-notes-redraw
  "k" #'agent-shell-notes-delete
  "D" #'agent-shell-notes-delete-marked
  "x" #'agent-shell-notes-purge-archived
  "e" #'agent-shell-notes-edit
  "C-c C-c" #'agent-shell-notes-send
  "w" #'agent-shell-notes-copy
  "C-c C-r" #'agent-shell-notes-restore-last
  "C-c C-e" #'agent-shell-notes-edit-mode
  "C-x C-q" #'agent-shell-notes-edit-mode
  "q" #'quit-window)

(define-derived-mode agent-shell-notes-review-mode markdown-mode "Notes"
  "Major mode of the review, where the collected notes are shown.
The buffer is drawn from the note list; its text is read-only.

\\{agent-shell-notes-review-mode-map}"
  (add-to-invisibility-spec '(agent-shell-notes-quote . t))
  (setq truncate-lines nil))

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
  :parent markdown-mode-map
  "C-c C-c" #'agent-shell-notes-edit-commit
  "C-c C-k" #'agent-shell-notes-edit-revert
  "C-c C-e" #'agent-shell-notes-edit-commit
  "C-x C-q" #'agent-shell-notes-edit-commit)

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
    ('file (cons (plist-get (alist-get :location note) :file)
                 (alist-get :project note)))
    ('dired (cons (plist-get (alist-get :location note) :directory)
                  (alist-get :project note)))
    ;; `buffer', and any source added by the user.
    (_ (plist-get (alist-get :location note) :buffer))))

(defun agent-shell-notes--group-heading (note)
  "Return the review heading of the group NOTE belongs to."
  (pcase (alist-get :source note)
    ('file (let ((project (alist-get :project note)))
             (format "# %s — %s"
                     (file-relative-name
                      (plist-get (alist-get :location note) :file) project)
                     (abbreviate-file-name
                      (directory-file-name project)))))
    ('dired (let ((project (alist-get :project note)))
              (format "# %s — %s"
                      (file-relative-name
                       (plist-get (alist-get :location note) :directory)
                       project)
                      (abbreviate-file-name
                       (directory-file-name project)))))
    (_ (format "# %s" (plist-get (alist-get :location note) :buffer)))))

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
        (quote (alist-get :quote note))
        (text (alist-get :text note)))
    (agent-shell-notes--insert-field
     'location
     (propertize (concat (format "**%s**"
                                 (pcase (alist-get :source note)
                                   ('dired (agent-shell-notes--dired-names
                                            note (plist-get
                                                  (alist-get :location note)
                                                  :directory)))
                                   (_ (agent-shell-notes--range-string
                                       (alist-get :location note)))))
                         (when-let* ((target (alist-get :archived note)))
                           (format " `sent to %s`" target)))
                 'face 'agent-shell-notes-location))
    (insert "\n")
    (when quote
      (let ((fence (agent-shell-notes--fence quote)))
        (insert fence "\n")
        (let ((qbeg (point)))
          (insert quote)
          (agent-shell-notes--fold-quote
           qbeg (point) (memq id agent-shell-notes--unfolded)))
        (insert "\n" fence "\n")))
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
      ;; An overlay, so font-lock does not wipe it.
      (let ((ov (make-overlay beg (point) nil t)))
        (overlay-put ov 'face 'agent-shell-notes-archived)
        (overlay-put ov 'evaporate t)))
    (when (memq id agent-shell-notes--marks)
      (agent-shell-notes--show-mark id beg (point)))))

(defvar agent-shell-notes-request-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map markdown-mode-map)
    ;; Keys a text-property map leaves unbound fall through to the
    ;; review's map, so the printing characters must insert here.
    (dotimes (i 95)
      (let ((key (string (+ 32 i))))
        (unless (lookup-key markdown-mode-map key)
          (keymap-set map (key-description key) #'self-insert-command))))
    (keymap-set map "C-c C-c" #'agent-shell-notes-send)
    map)
  "Keymap of the request body in the review.
It is the body's `keymap' text property, so it shadows the review's
note keys there and letters insert.")

(defvar-local agent-shell-notes--request-start nil
  "Marker at the start of the request body in the review.
The body runs from here to the end of the buffer.")

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
`read-only', so text typed into an empty body is writable and takes
the request keymap.  Edit mode leaves the keymap off, so its own keys
work in the body too."
  (let ((props (append (list 'agent-shell-notes-field 'request)
                       (unless agent-shell-notes-edit-mode
                         (list 'keymap agent-shell-notes-request-map)))))
    (insert (propertize "# Request\n\n" 'read-only t))
    (add-text-properties (1- (point)) (point)
                         (append '(rear-nonsticky (read-only)) props))
    (setq agent-shell-notes--request-start (point-marker))
    (insert (apply #'propertize request props))))

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
  (let ((id (get-text-property (point) 'agent-shell-notes-id)))
    (unless id
      (user-error "No note at point"))
    (setq agent-shell-notes--notes
          (seq-remove (lambda (note) (eql id (alist-get :id note)))
                      agent-shell-notes--notes)
          agent-shell-notes--unfolded (delq id agent-shell-notes--unfolded)
          agent-shell-notes--marks (delq id agent-shell-notes--marks))
    (agent-shell-notes--review-draw)))

;;;; Send and copy

(defcustom agent-shell-notes-agent-shell-disposition nil
  "How the agent-shell client sends to a busy shell.
nil leaves it to `agent-shell-busy-submit-default-function'; `queue'
queues the prompt; `steer' steers the running turn."
  :type '(choice (const :tag "agent-shell default" nil)
                 (const :tag "Queue" queue)
                 (const :tag "Steer" steer)))

(defun agent-shell-notes--directory (dir)
  "Return DIR expanded, as a directory name."
  (file-name-as-directory (expand-file-name dir)))

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
  (let* ((notes (agent-shell-notes--selected-notes))
         (client agent-shell-notes-client)
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
                (funcall (plist-get client :project) session))))
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
