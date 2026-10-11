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

(defcustom agent-shell-notes-sources
  '((file buffer-file-name agent-shell-notes--file-extract))
  "Source types tried in order by `agent-shell-notes-capture'.
Each entry is (SYMBOL PREDICATE EXTRACT).  The first entry whose
PREDICATE, called with no arguments in the buffer being captured,
returns non-nil captures.  EXTRACT is then called the same way and
returns a plist:

  :location  the note's location, as described for SYMBOL's source
  :quote     the text copied from the source, or nil
  :beg :end  buffer positions of the captured extent, kept as markers

SYMBOL becomes the note's `:source'."
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

(defun agent-shell-notes--fence (text)
  "Return a backtick fence longer than any backtick run in TEXT."
  (let ((longest 2)
        (start 0))
    (while (string-match "`+" text start)
      (setq longest (max longest (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    (make-string (1+ longest) ?`)))

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
             (concat (file-relative-name (plist-get loc :file)
                                         (alist-get :project note))
                     " " (agent-shell-notes--range-string loc))
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
  "e" #'agent-shell-notes-edit
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
                 (alist-get :project note)))))

(defun agent-shell-notes--group-heading (note)
  "Return the review heading of the group NOTE belongs to."
  (pcase (alist-get :source note)
    ('file (let ((project (alist-get :project note)))
             (format "# %s — %s"
                     (file-relative-name
                      (plist-get (alist-get :location note) :file) project)
                     (abbreviate-file-name
                      (directory-file-name project)))))))

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
     (propertize (format "**%s**" (agent-shell-notes--range-string
                                   (alist-get :location note)))
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
    (when (memq id agent-shell-notes--marks)
      (agent-shell-notes--show-mark id beg (point)))))

(defun agent-shell-notes--review-draw ()
  "Redraw the current review buffer from the note list.
Point stays on the note it was on."
  (let ((id (get-text-property (point) 'agent-shell-notes-id))
        (pos (point))
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
