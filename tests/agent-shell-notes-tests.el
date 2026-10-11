;;; agent-shell-notes-tests.el --- Tests for agent-shell-notes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; Copyright (C) 2026 Bill and contributors

;;; Commentary:

;; Batch ERT against the real agent-shell fork, Magit and markdown-mode.
;; Run with `make test'; the Makefile puts the dependencies on the load path.

;;; Code:

(require 'ert)
(require 'agent-shell-notes)

(ert-deftest agent-shell-notes-loads-with-real-agent-shell ()
  (should (featurep 'agent-shell-notes))
  (should (featurep 'agent-shell))
  (should (featurep 'markdown-mode))
  ;; The fragment renderer the transcript tests will build buffers with.
  (should (fboundp 'agent-shell--update-fragment))
  ;; Only Bill's fork defines it; upstream agent-shell would fail here.
  (should (fboundp 'agent-shell-fork)))

(ert-deftest agent-shell-notes-magit-is-on-the-load-path ()
  ;; Magit is a soft dependency of the package but a hard one of the tests:
  ;; diff buffers come from the real `magit-diff-setup-buffer'.
  (should (require 'magit nil t))
  (should (fboundp 'magit-diff-setup-buffer)))

;;;; File capture and the popup

(defmacro agent-shell-notes-tests--with-clean-state (&rest body)
  "Run BODY with an empty note list and no package buffers left behind."
  (declare (indent 0) (debug t))
  `(let ((agent-shell-notes--notes nil)
         (agent-shell-notes--next-id 0)
         (agent-shell-notes--marks nil)
         (agent-shell-notes--last-target nil)
         (agent-shell-notes--last-send nil)
         (agent-shell-notes-after-send agent-shell-notes-after-send)
         (agent-shell-notes-tests--shells nil)
         (kill-ring nil))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           ,@body)
       ;; Viewports go first, after the windows are restored, so their
       ;; clean-up hook never looks for a shell to kill.
       (dolist (shell agent-shell-notes-tests--shells)
         (when-let* ((viewport (get-buffer
                                (concat (buffer-name shell) " [viewport]"))))
           (kill-buffer viewport)))
       (mapc #'kill-buffer agent-shell-notes-tests--shells)
       (dolist (name '("*agent-shell-notes*" "*agent-shell-notes capture*"))
         (when (get-buffer name)
           (kill-buffer name))))))

(defvar agent-shell-notes-tests--shells nil
  "Fake shell buffers made by the test running now.")

(defun agent-shell-notes-tests--file (lines &optional name)
  "Visit a fresh temporary file holding LINES; return its buffer.
NAME is the file's base name, default \"sample.el\".  The file lives
in its own temporary directory, which is not inside a project."
  (let* ((dir (file-name-as-directory (make-temp-file "asn-test-" t)))
         (file (expand-file-name (or name "sample.el") dir)))
    (with-temp-file file
      (insert (mapconcat #'identity lines "\n") "\n"))
    (find-file-noselect file)))

(defun agent-shell-notes-tests--lines (n)
  "Return N lines \"line 1\" .. \"line N\"."
  (mapcar (lambda (i) (format "line %d" i)) (number-sequence 1 n)))

(defun agent-shell-notes-tests--goto-line (n)
  (goto-char (point-min))
  (forward-line (1- n)))

(defun agent-shell-notes-tests--select (buffer line &optional end-line)
  "Show BUFFER in the selected window with point on LINE.
With END-LINE, activate a region from LINE to the start of END-LINE."
  (switch-to-buffer buffer)
  (transient-mark-mode 1)
  (deactivate-mark)
  (agent-shell-notes-tests--goto-line line)
  (when end-line
    (push-mark (point) t t)
    (agent-shell-notes-tests--goto-line end-line)))

(defun agent-shell-notes-tests--capture (buffer line &optional end-line text)
  "Capture in BUFFER at LINE (region to the start of END-LINE), save TEXT.
Return the saved note."
  (agent-shell-notes-tests--select buffer line end-line)
  (agent-shell-notes-capture)
  (with-current-buffer "*agent-shell-notes capture*"
    (goto-char (point-max))
    (insert (or text ""))
    (agent-shell-notes-capture-save))
  (car (last agent-shell-notes--notes)))

(ert-deftest agent-shell-notes-capture-current-line-in-file ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((buf (agent-shell-notes-tests--file
                 (agent-shell-notes-tests--lines 5)))
           (file (buffer-file-name buf))
           (note (agent-shell-notes-tests--capture buf 3 nil "hoist it")))
      (should (= 1 (length agent-shell-notes--notes)))
      (should (equal 1 (alist-get :id note)))
      (should (eq 'file (alist-get :source note)))
      (should (equal (file-name-directory file) (alist-get :project note)))
      (should (equal `(:file ,file :start 3 :end 3)
                     (alist-get :location note)))
      (should (equal "line 3" (alist-get :quote note)))
      (should (equal "hoist it" (alist-get :text note)))
      (should (null (alist-get :archived note)))
      (should (time-less-p (alist-get :created note)
                           (time-add (current-time) 1)))
      (pcase-let ((`(,mbuf ,beg ,end) (alist-get :markers note)))
        (should (eq buf mbuf))
        (should (markerp beg))
        (should (markerp end))
        (should (equal "line 3" (with-current-buffer buf
                                  (buffer-substring beg end))))))))

(ert-deftest agent-shell-notes-capture-region-in-file ()
  ;; A region ending at the start of line 5 covers lines 2-4.
  (agent-shell-notes-tests--with-clean-state
    (let* ((buf (agent-shell-notes-tests--file
                 (agent-shell-notes-tests--lines 6)))
           (note (agent-shell-notes-tests--capture buf 2 5 "three lines")))
      (should (equal 2 (plist-get (alist-get :location note) :start)))
      (should (equal 4 (plist-get (alist-get :location note) :end)))
      (should (equal "line 2\nline 3\nline 4" (alist-get :quote note)))
      (should-not (with-current-buffer buf (region-active-p))))))

(ert-deftest agent-shell-notes-capture-region-mid-line-takes-whole-lines ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 6))))
      (agent-shell-notes-tests--select buf 2)
      (forward-char 3)
      (push-mark (point) t t)
      (agent-shell-notes-tests--goto-line 3)
      (forward-char 2)
      (agent-shell-notes-capture)
      (with-current-buffer "*agent-shell-notes capture*"
        (agent-shell-notes-capture-save))
      (let ((note (car agent-shell-notes--notes)))
        (should (equal '(2 . 3)
                       (cons (plist-get (alist-get :location note) :start)
                             (plist-get (alist-get :location note) :end))))
        (should (equal "line 2\nline 3" (alist-get :quote note)))))))

(ert-deftest agent-shell-notes-capture-popup-layout ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 3))))
      (agent-shell-notes-tests--select buf 2)
      (agent-shell-notes-capture)
      (should (equal "*agent-shell-notes capture*"
                     (buffer-name (window-buffer (selected-window)))))
      ;; Shown in a new window below the source, not over it.
      (should (= 2 (count-windows)))
      (should (eq buf (window-buffer (window-in-direction 'above))))
      (with-current-buffer "*agent-shell-notes capture*"
        (should (eq major-mode 'agent-shell-notes-capture-mode))
        (should header-line-format)
        ;; Point waits in the note area, after the read-only header.
        (should (= (point) (point-max)))
        (should (string-match-p "sample.el line 2"
                                (buffer-substring (point-min) (point-max))))
        (should (string-match-p "^line 2$"
                                (buffer-substring (point-min) (point-max))))
        (save-excursion
          (goto-char (point-min))
          (should-error (insert "x") :type 'text-read-only))
        (insert "typed")
        (should (equal "typed" (buffer-substring
                                (line-beginning-position) (point))))))))

(ert-deftest agent-shell-notes-capture-abort-saves-nothing ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 3))))
      (agent-shell-notes-tests--select buf 2)
      (agent-shell-notes-capture)
      (insert "never mind")
      (agent-shell-notes-capture-abort)
      (should (null agent-shell-notes--notes))
      (should-not (get-buffer "*agent-shell-notes capture*"))
      (should (= 1 (count-windows)))
      (should (eq buf (window-buffer (selected-window)))))))

(ert-deftest agent-shell-notes-capture-empty-text-saves-quote-only ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((buf (agent-shell-notes-tests--file
                 (agent-shell-notes-tests--lines 3)))
           (note (agent-shell-notes-tests--capture buf 1 nil "  \n ")))
      (should (= 1 (length agent-shell-notes--notes)))
      (should (equal "" (alist-get :text note)))
      (should (equal "line 1" (alist-get :quote note)))
      ;; Save restored the window configuration too.
      (should (= 1 (count-windows)))
      (should (eq buf (window-buffer (selected-window)))))))

(ert-deftest agent-shell-notes-capture-second-capture-switches-to-popup ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--select buf 2)
      (agent-shell-notes-capture)
      (insert "first draft")
      ;; Back in the source, on another line, capture again.
      (select-window (window-in-direction 'above))
      (agent-shell-notes-tests--goto-line 4)
      (agent-shell-notes-capture)
      (should (= 2 (count-windows)))
      (should (equal "*agent-shell-notes capture*"
                     (buffer-name (window-buffer (selected-window)))))
      (agent-shell-notes-capture-save)
      (should (= 1 (length agent-shell-notes--notes)))
      (let ((note (car agent-shell-notes--notes)))
        (should (equal 2 (plist-get (alist-get :location note) :start)))
        (should (equal "first draft" (alist-get :text note))))
      (should (= 1 (count-windows))))))

(defun agent-shell-notes-tests--search (regexp)
  "Return the start of the first match of REGEXP in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward regexp)
    (match-beginning 0)))

(ert-deftest agent-shell-notes-capture-popup-folds-long-quote ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 9))))
      (agent-shell-notes-tests--select buf 1 10)
      (agent-shell-notes-capture)
      (with-current-buffer "*agent-shell-notes capture*"
        (should-not (invisible-p (agent-shell-notes-tests--search "^line 6$")))
        (should (invisible-p (agent-shell-notes-tests--search "^line 7$")))
        (should (invisible-p (agent-shell-notes-tests--search "^line 9$")))
        (let ((note-area (point)))
          (goto-char (agent-shell-notes-tests--search "^line 2$"))
          (agent-shell-notes-toggle-quote)
          (should-not (invisible-p (agent-shell-notes-tests--search
                                    "^line 7$")))
          (agent-shell-notes-toggle-quote)
          (should (invisible-p (agent-shell-notes-tests--search "^line 7$")))
          (should (eq (lookup-key agent-shell-notes-capture-mode-map
                                  (kbd "TAB"))
                      'agent-shell-notes-toggle-quote))
          (goto-char note-area))))))

(ert-deftest agent-shell-notes-capture-popup-short-quote-not-folded ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 6))))
      (agent-shell-notes-tests--select buf 1 7)
      (agent-shell-notes-capture)
      (with-current-buffer "*agent-shell-notes capture*"
        (should-not (invisible-p (agent-shell-notes-tests--search
                                  "^line 6$")))))))

(defvar evil-state)
(declare-function evil-mode "evil-core" (&optional arg))

(ert-deftest agent-shell-notes-capture-popup-opens-in-evil-insert-state ()
  (skip-unless (require 'evil nil t))
  (agent-shell-notes-tests--with-clean-state
    (let ((was-on (bound-and-true-p evil-mode))
          (buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 3))))
      (unwind-protect
          (progn
            (evil-mode 1)
            (agent-shell-notes-tests--select buf 2)
            (agent-shell-notes-capture)
            (with-current-buffer "*agent-shell-notes capture*"
              (should (eq 'insert evil-state))
              ;; Save stays reachable from insert state.
              (should (eq 'agent-shell-notes-capture-save
                          (key-binding (kbd "C-c C-c"))))))
        (unless was-on
          (evil-mode -1))))))

;;;; The review

(defun agent-shell-notes-tests--runs (prop)
  "Return the values of PROP in the current buffer, one per run, in order.
Runs where PROP is nil are skipped."
  (let ((pos (point-min))
        values)
    (while (< pos (point-max))
      (when-let* ((value (get-text-property pos prop)))
        (push value values))
      (setq pos (next-single-property-change pos prop nil (point-max))))
    (nreverse values)))

(defun agent-shell-notes-tests--note-fields (id)
  "Return the field runs, in order, inside review note ID."
  (save-restriction
    (let ((beg (text-property-any (point-min) (point-max)
                                  'agent-shell-notes-id id)))
      (narrow-to-region beg (next-single-property-change
                             beg 'agent-shell-notes-id nil (point-max)))
      (agent-shell-notes-tests--runs 'agent-shell-notes-field))))

(defun agent-shell-notes-tests--field-text (id field)
  "Return the text of FIELD inside review note ID."
  (let* ((beg (text-property-any (point-min) (point-max)
                                 'agent-shell-notes-id id))
         (end (next-single-property-change beg 'agent-shell-notes-id
                                           nil (point-max)))
         (fbeg (text-property-any beg end 'agent-shell-notes-field field)))
    (buffer-substring-no-properties
     fbeg (next-single-property-change fbeg 'agent-shell-notes-field
                                       nil end))))

(ert-deftest agent-shell-notes-review-shows-a-note ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((buf (agent-shell-notes-tests--file
                 (agent-shell-notes-tests--lines 5)))
           (file (buffer-file-name buf)))
      (agent-shell-notes-tests--capture buf 2 4 "hoist it")
      (agent-shell-notes-review)
      (should (equal "*agent-shell-notes*"
                     (buffer-name (window-buffer (selected-window)))))
      (with-current-buffer "*agent-shell-notes*"
        (should (eq major-mode 'agent-shell-notes-review-mode))
        (should (equal '(1) (agent-shell-notes-tests--runs
                             'agent-shell-notes-id)))
        (should (equal (list (cons file (file-name-directory file)))
                       (agent-shell-notes-tests--runs
                        'agent-shell-notes-group)))
        (should (equal '(location quote text)
                       (agent-shell-notes-tests--note-fields 1)))
        (should (equal "line 2\nline 3"
                       (agent-shell-notes-tests--field-text 1 'quote)))
        (should (equal "hoist it"
                       (agent-shell-notes-tests--field-text 1 'text)))
        ;; Everything drawn so far is read-only.
        (should-not (text-property-not-all (point-min) (point-max)
                                           'read-only t))
        (should-error (insert "x") :type 'text-read-only)))))

(ert-deftest agent-shell-notes-review-quote-only-note-has-no-text-field ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2)
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should (equal '(location quote)
                       (agent-shell-notes-tests--note-fields 1)))))))

(ert-deftest agent-shell-notes-review-groups-and-orders-notes ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((a (agent-shell-notes-tests--file
               (agent-shell-notes-tests--lines 9) "a.el"))
           (b (agent-shell-notes-tests--file
               (agent-shell-notes-tests--lines 9) "b.el"))
           (a-key (cons (buffer-file-name a)
                        (file-name-directory (buffer-file-name a))))
           (b-key (cons (buffer-file-name b)
                        (file-name-directory (buffer-file-name b)))))
      (agent-shell-notes-tests--capture a 5 nil "a5")  ; id 1
      (agent-shell-notes-tests--capture b 1 nil "b1")  ; id 2
      (agent-shell-notes-tests--capture a 2 nil "a2")  ; id 3
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        ;; Groups by first capture (a.el first), notes by line.
        (should (equal (list a-key b-key)
                       (agent-shell-notes-tests--runs
                        'agent-shell-notes-group)))
        (should (equal '(3 1 2) (agent-shell-notes-tests--runs
                                 'agent-shell-notes-id))))
      ;; A capture while the review is open lands in place.
      (agent-shell-notes-tests--capture a 3 nil "a3")  ; id 4
      (with-current-buffer "*agent-shell-notes*"
        (should (equal '(3 4 1 2) (agent-shell-notes-tests--runs
                                   'agent-shell-notes-id)))))))

(ert-deftest agent-shell-notes-review-window-keeps-its-note-on-redraw ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 9))))
      (agent-shell-notes-tests--capture buf 5 nil "five")  ; id 1
      (agent-shell-notes-tests--capture buf 8 nil "eight") ; id 2
      (agent-shell-notes-review)
      (let ((review-window (selected-window)))
        (goto-char (text-property-any (point-min) (point-max)
                                      'agent-shell-notes-id 2))
        ;; Capture from another window while the review stays shown.
        (select-window (split-window review-window nil 'above))
        (agent-shell-notes-tests--capture buf 1 nil "one")  ; id 3
        (should (eq 2 (get-text-property (window-point review-window)
                                         'agent-shell-notes-id
                                         (window-buffer review-window))))))))

(defun agent-shell-notes-tests--key (key)
  "Run the review command bound to KEY."
  (let ((command (keymap-lookup agent-shell-notes-review-mode-map key)))
    (should (commandp command))
    (call-interactively command)))

(defun agent-shell-notes-tests--at-note-start-p (id)
  "Non-nil when point is at the first character of review note ID."
  (and (eq id (get-text-property (point) 'agent-shell-notes-id))
       (or (bobp)
           (not (eq id (get-text-property (1- (point))
                                          'agent-shell-notes-id))))))

(ert-deftest agent-shell-notes-review-next-and-previous-note ()
  (agent-shell-notes-tests--with-clean-state
    (let ((a (agent-shell-notes-tests--file
              (agent-shell-notes-tests--lines 9) "a.el"))
          (b (agent-shell-notes-tests--file
              (agent-shell-notes-tests--lines 9) "b.el")))
      (agent-shell-notes-tests--capture a 5 nil "a5")  ; id 1
      (agent-shell-notes-tests--capture b 1)           ; id 2
      (agent-shell-notes-tests--capture a 2 nil "a2")  ; id 3
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (goto-char (point-min))
        ;; Review order is 3 1 2; n crosses the group heading.
        (agent-shell-notes-tests--key "n")
        (should (agent-shell-notes-tests--at-note-start-p 3))
        (agent-shell-notes-tests--key "n")
        (should (agent-shell-notes-tests--at-note-start-p 1))
        (agent-shell-notes-tests--key "n")
        (should (agent-shell-notes-tests--at-note-start-p 2))
        ;; No note after the last one: point stays.
        (ignore-errors (agent-shell-notes-tests--key "n"))
        (should (agent-shell-notes-tests--at-note-start-p 2))
        ;; From inside a note, p goes to the previous note's start.
        (forward-line 1)
        (agent-shell-notes-tests--key "p")
        (should (agent-shell-notes-tests--at-note-start-p 1))
        (agent-shell-notes-tests--key "p")
        (should (agent-shell-notes-tests--at-note-start-p 3))
        (ignore-errors (agent-shell-notes-tests--key "p"))
        (should (agent-shell-notes-tests--at-note-start-p 3))))))

(ert-deftest agent-shell-notes-review-tab-folds-quote-across-redraw ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 12))))
      (agent-shell-notes-tests--capture buf 1 11 "long")  ; id 1
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should-not (invisible-p (agent-shell-notes-tests--search "^line 6$")))
        (should (invisible-p (agent-shell-notes-tests--search "^line 7$")))
        (goto-char (agent-shell-notes-tests--search "^\\*\\*lines"))
        (agent-shell-notes-tests--key "TAB")
        (should-not (invisible-p (agent-shell-notes-tests--search
                                  "^line 7$")))
        (agent-shell-notes-tests--key "g")
        (should-not (invisible-p (agent-shell-notes-tests--search
                                  "^line 7$")))
        (agent-shell-notes-tests--key "TAB")
        (should (invisible-p (agent-shell-notes-tests--search "^line 7$")))))))

(ert-deftest agent-shell-notes-review-g-redraws-and-q-quits ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 1)
      (agent-shell-notes-tests--capture buf 2)
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should (equal '(1 2) (agent-shell-notes-tests--runs
                               'agent-shell-notes-id)))
        (setq agent-shell-notes--notes (last agent-shell-notes--notes))
        (agent-shell-notes-tests--key "g")
        (should (equal '(2) (agent-shell-notes-tests--runs
                             'agent-shell-notes-id)))
        (should (eq (get-buffer "*agent-shell-notes*")
                    (window-buffer (selected-window))))
        (agent-shell-notes-tests--key "q")
        (should-not (eq (get-buffer "*agent-shell-notes*")
                        (window-buffer (selected-window))))))))

;;;; Marks

(defun agent-shell-notes-tests--marked ()
  "Return the ids of the review notes shown marked, in buffer order.
A note is shown marked when a mark overlay covers or starts at it."
  (let (ids)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when-let* ((id (overlay-get ov 'agent-shell-notes-mark)))
        (should (eq id (get-text-property (overlay-start ov)
                                          'agent-shell-notes-id)))
        (push (cons (overlay-start ov) id) ids)))
    (delete-dups (mapcar #'cdr (sort ids (lambda (a b) (< (car a) (car b))))))))

(defun agent-shell-notes-tests--goto-note (id)
  (goto-char (text-property-any (point-min) (point-max)
                                'agent-shell-notes-id id)))

(defun agent-shell-notes-tests--review-with (n)
  "Capture N one-line notes from one file and open the review on it.
Note I is on line I, so the review order is 1 .. N."
  (let ((buf (agent-shell-notes-tests--file
              (agent-shell-notes-tests--lines (max n 3)))))
    (dotimes (i n)
      (agent-shell-notes-tests--capture buf (1+ i) nil (format "n%d" (1+ i))))
    (agent-shell-notes-review)
    (set-buffer "*agent-shell-notes*")
    buf))

(ert-deftest agent-shell-notes-review-m-marks-and-moves-to-next ()
  (agent-shell-notes-tests--with-clean-state
    (agent-shell-notes-tests--review-with 3)
    (agent-shell-notes-tests--goto-note 1)
    (forward-line 1)
    (agent-shell-notes-tests--key "m")
    (should (equal '(1) (agent-shell-notes-tests--marked)))
    (should (agent-shell-notes-tests--at-note-start-p 2))
    (agent-shell-notes-tests--key "m")
    (should (equal '(1 2) (agent-shell-notes-tests--marked)))
    (should (agent-shell-notes-tests--at-note-start-p 3))
    ;; On the last note: mark and stay.
    (agent-shell-notes-tests--key "m")
    (should (equal '(1 2 3) (agent-shell-notes-tests--marked)))
    (should (eq 3 (get-text-property (point) 'agent-shell-notes-id)))))

(ert-deftest agent-shell-notes-review-u-unmarks-and-moves-to-next ()
  (agent-shell-notes-tests--with-clean-state
    (agent-shell-notes-tests--review-with 3)
    (agent-shell-notes-tests--goto-note 1)
    (dotimes (_ 3) (agent-shell-notes-tests--key "m"))
    (agent-shell-notes-tests--goto-note 2)
    (agent-shell-notes-tests--key "u")
    (should (equal '(1 3) (agent-shell-notes-tests--marked)))
    (should (agent-shell-notes-tests--at-note-start-p 3))
    ;; Unmarking an unmarked note is harmless.
    (agent-shell-notes-tests--goto-note 2)
    (agent-shell-notes-tests--key "u")
    (should (equal '(1 3) (agent-shell-notes-tests--marked)))))

(ert-deftest agent-shell-notes-review-m-and-u-act-on-region ()
  (agent-shell-notes-tests--with-clean-state
    (transient-mark-mode 1)
    (agent-shell-notes-tests--review-with 4)
    ;; From inside note 1 to the start of note 3: touches 1 and 2 only.
    (agent-shell-notes-tests--goto-note 1)
    (forward-line 1)
    (push-mark (point) t t)
    (agent-shell-notes-tests--goto-note 3)
    (agent-shell-notes-tests--key "m")
    (should (equal '(1 2) (agent-shell-notes-tests--marked)))
    (should-not (region-active-p))
    (should (agent-shell-notes-tests--at-note-start-p 3))
    ;; A region from the middle of note 2 into note 4 unmarks 2, leaves 1.
    (agent-shell-notes-tests--goto-note 2)
    (forward-line 1)
    (push-mark (point) t t)
    (agent-shell-notes-tests--goto-note 4)
    (forward-char 1)
    (agent-shell-notes-tests--key "u")
    (should (equal '(1) (agent-shell-notes-tests--marked)))
    (should (eq 4 (get-text-property (point) 'agent-shell-notes-id)))))

(ert-deftest agent-shell-notes-review-t-toggles-and-U-unmarks-all ()
  (agent-shell-notes-tests--with-clean-state
    (agent-shell-notes-tests--review-with 3)
    ;; From none, t marks all.
    (agent-shell-notes-tests--key "t")
    (should (equal '(1 2 3) (agent-shell-notes-tests--marked)))
    (agent-shell-notes-tests--key "t")
    (should (equal '() (agent-shell-notes-tests--marked)))
    ;; From some, t inverts each mark.
    (agent-shell-notes-tests--goto-note 2)
    (agent-shell-notes-tests--key "m")
    (agent-shell-notes-tests--key "t")
    (should (equal '(1 3) (agent-shell-notes-tests--marked)))
    (agent-shell-notes-tests--key "U")
    (should (equal '() (agent-shell-notes-tests--marked)))
    ;; U with nothing marked is harmless.
    (agent-shell-notes-tests--key "U")
    (should (equal '() (agent-shell-notes-tests--marked)))))

(ert-deftest agent-shell-notes-review-t-skips-archived-notes ()
  (agent-shell-notes-tests--with-clean-state
    (agent-shell-notes-tests--review-with 3)
    (setf (alist-get :archived (nth 1 agent-shell-notes--notes))
          "Claude Agent @ x")
    (agent-shell-notes-tests--key "g")
    (agent-shell-notes-tests--key "t")
    (should (equal '(1 3) (agent-shell-notes-tests--marked)))
    ;; An archived note can still be marked by hand; t leaves it marked.
    (agent-shell-notes-tests--goto-note 2)
    (agent-shell-notes-tests--key "m")
    (agent-shell-notes-tests--key "t")
    (should (equal '(2) (agent-shell-notes-tests--marked)))
    (agent-shell-notes-tests--key "U")
    (should (equal '() (agent-shell-notes-tests--marked)))))

(ert-deftest agent-shell-notes-review-marks-survive-redraw-and-capture ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--review-with 3)))
      (agent-shell-notes-tests--goto-note 2)
      (agent-shell-notes-tests--key "m")
      (agent-shell-notes-tests--key "g")
      (should (equal '(2) (agent-shell-notes-tests--marked)))
      ;; A capture while the review is shown redraws it in place.
      (let ((review-window (selected-window)))
        (select-window (split-window review-window nil 'above))
        (agent-shell-notes-tests--capture buf 3 nil "again")  ; id 4
        (with-current-buffer "*agent-shell-notes*"
          (should (equal '(1 2 3 4) (agent-shell-notes-tests--runs
                                     'agent-shell-notes-id)))
          (should (equal '(2) (agent-shell-notes-tests--marked))))))))

(ert-deftest agent-shell-notes-review-mark-off-a-note-signals ()
  (agent-shell-notes-tests--with-clean-state
    (transient-mark-mode 1)
    (agent-shell-notes-tests--review-with 2)
    ;; Point on the group heading: no note.
    (goto-char (point-min))
    (dolist (key '("m" "u"))
      (should (equal "No note at point"
                     (cadr (should-error (agent-shell-notes-tests--key key)
                                         :type 'user-error)))))
    ;; A region over the heading alone touches no note.
    (push-mark (point) t t)
    (end-of-line)
    (should-error (agent-shell-notes-tests--key "m") :type 'user-error)
    (should (equal '() (agent-shell-notes-tests--marked)))))

(ert-deftest agent-shell-notes-review-mark-indicator-background ()
  (agent-shell-notes-tests--with-clean-state
    (let ((agent-shell-notes-mark-indicator 'background))
      (agent-shell-notes-tests--review-with 2)
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "m")
      (let ((ov (seq-find (lambda (ov) (overlay-get ov 'agent-shell-notes-mark))
                          (overlays-in (point-min) (point-max)))))
        (should (eq 'agent-shell-notes-mark (overlay-get ov 'face)))
        ;; The face covers the whole note.
        (agent-shell-notes-tests--goto-note 1)
        (should (= (point) (overlay-start ov)))
        (should (= (next-single-property-change (point) 'agent-shell-notes-id)
                   (overlay-end ov))))
      ;; Marks are overlays, never text.
      (should (equal '("n1" "n2")
                     (list (agent-shell-notes-tests--field-text 1 'text)
                           (agent-shell-notes-tests--field-text 2 'text))))
      (should-not (string-match-p "\\*\\*lines\\|^\\*$"
                                  (buffer-substring-no-properties
                                   (point-min) (point-max)))))))

(ert-deftest agent-shell-notes-review-mark-indicator-fringe-on-tty ()
  ;; Batch has no graphic display, so `fringe' takes its tty branch.
  (agent-shell-notes-tests--with-clean-state
    (let ((agent-shell-notes-mark-indicator 'fringe)
          (text-before nil))
      (agent-shell-notes-tests--review-with 2)
      (setq text-before (buffer-string))
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "m")
      (should (equal text-before (buffer-string)))
      (let* ((ov (seq-find (lambda (ov) (overlay-get ov 'agent-shell-notes-mark))
                           (overlays-in (point-min) (point-max))))
             (display (get-text-property 0 'display
                                         (overlay-get ov 'before-string))))
        (should (equal '(margin left-margin) (car display)))
        (should (equal "*" (substring-no-properties (cadr display))))
        (should-not (overlay-get ov 'face)))
      (should (= 1 left-margin-width))
      (should (= 1 (car (window-margins
                         (get-buffer-window "*agent-shell-notes*"))))))))

;;;; Edit mode and deletion

(defun agent-shell-notes-tests--writable-p (pos)
  "Non-nil when inserting a character at POS succeeds; the buffer is restored."
  (condition-case nil
      (save-excursion
        (goto-char pos)
        (insert-and-inherit "x")
        (delete-char -1)
        t)
    (text-read-only nil)))

(defun agent-shell-notes-tests--note-pos (id)
  "Return the start of review note ID."
  (text-property-any (point-min) (point-max) 'agent-shell-notes-id id))

(ert-deftest agent-shell-notes-edit-mode-lifts-read-only-from-texts-only ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "hoist it")  ; id 1
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (agent-shell-notes-tests--key "C-x C-q")
        (should agent-shell-notes-edit-mode)
        ;; Batch `format-mode-line' returns "", so check the lighter entry.
        (should (equal " Edit" (cadr (assq 'agent-shell-notes-edit-mode
                                           minor-mode-alist))))
        (let ((text (agent-shell-notes-tests--search "^hoist it$")))
          (should (agent-shell-notes-tests--writable-p text))
          (should (agent-shell-notes-tests--writable-p (+ text 3)))
          (should (agent-shell-notes-tests--writable-p (+ text 8))))
        ;; Heading, location and quote stay read-only.
        (should-not (agent-shell-notes-tests--writable-p (point-min)))
        (should-not (agent-shell-notes-tests--writable-p
                     (1+ (agent-shell-notes-tests--search "^\\*\\*line"))))
        (should-not (agent-shell-notes-tests--writable-p
                     (1+ (agent-shell-notes-tests--search "^line 2$"))))))))

(defun agent-shell-notes-tests--type (string)
  "Type STRING at point as if from the keyboard, one character at a time."
  (dolist (char (string-to-list string))
    (let ((last-command-event char))
      (call-interactively (key-binding (vector char))))))

(defun agent-shell-notes-tests--edit-key (key)
  "Run the command KEY runs in the current buffer."
  (let ((command (key-binding (kbd key))))
    (should (commandp command))
    (call-interactively command)))

(defun agent-shell-notes-tests--note-text (id)
  (alist-get :text (seq-find (lambda (note) (eql id (alist-get :id note)))
                             agent-shell-notes--notes)))

(ert-deftest agent-shell-notes-edit-mode-commit-saves-changed-texts ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "hoist it")  ; id 1
      (agent-shell-notes-tests--capture buf 4 nil "rename")    ; id 2
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (agent-shell-notes-tests--key "C-x C-q")
        ;; Typed at the start and the end of a text, not via `insert'.
        (goto-char (agent-shell-notes-tests--search "^hoist it$"))
        (agent-shell-notes-tests--type "please ")
        (end-of-line)
        (agent-shell-notes-tests--type " now")
        (agent-shell-notes-tests--edit-key "C-c C-c")
        (should-not agent-shell-notes-edit-mode)
        (should (equal "please hoist it now"
                       (agent-shell-notes-tests--note-text 1)))
        (should (equal "rename" (agent-shell-notes-tests--note-text 2)))
        (should (equal "please hoist it now"
                       (agent-shell-notes-tests--field-text 1 'text)))
        ;; Back to the note keys and an all read-only buffer.
        (should (eq 'agent-shell-notes-next-note (key-binding (kbd "n"))))
        (should-not (text-property-not-all (point-min) (point-max)
                                           'read-only t))
        (should-not (buffer-modified-p))))))

(ert-deftest agent-shell-notes-edit-mode-revert-drops-changes ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "hoist it")
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (agent-shell-notes-tests--key "C-c C-e")
        (goto-char (agent-shell-notes-tests--search "^hoist it$"))
        (agent-shell-notes-tests--type "never ")
        (agent-shell-notes-tests--edit-key "C-c C-k")
        (should-not agent-shell-notes-edit-mode)
        (should (equal "hoist it" (agent-shell-notes-tests--note-text 1)))
        (should (equal "hoist it"
                       (agent-shell-notes-tests--field-text 1 'text)))
        (should-not (text-property-not-all (point-min) (point-max)
                                           'read-only t))))))

(ert-deftest agent-shell-notes-edit-mode-emptied-text-keeps-quote-only-note ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "hoist it")
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (agent-shell-notes-tests--key "C-x C-q")
        (let ((beg (agent-shell-notes-tests--search "^hoist it$")))
          (delete-region beg (+ beg (length "hoist it"))))
        (agent-shell-notes-tests--edit-key "C-c C-c")
        (should (= 1 (length agent-shell-notes--notes)))
        (should (equal "" (agent-shell-notes-tests--note-text 1)))
        (should (equal '(location quote)
                       (agent-shell-notes-tests--note-fields 1)))))))

(ert-deftest agent-shell-notes-edit-puts-point-in-the-note-text ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "hoist it")  ; id 1
      (agent-shell-notes-tests--capture buf 4)                 ; id 2, quote only
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should-error (progn (goto-char (point-min))
                             (agent-shell-notes-tests--key "e"))
                      :type 'user-error)
        (should-not agent-shell-notes-edit-mode)
        (goto-char (agent-shell-notes-tests--note-pos 2))
        (agent-shell-notes-tests--key "e")
        (should agent-shell-notes-edit-mode)
        (should (eq 2 (get-text-property (point) 'agent-shell-notes-id)))
        (agent-shell-notes-tests--type "new remark")
        (agent-shell-notes-tests--edit-key "C-c C-c")
        (should (equal "new remark" (agent-shell-notes-tests--note-text 2)))
        (should (equal "hoist it" (agent-shell-notes-tests--note-text 1)))
        (should (equal '(location quote text)
                       (agent-shell-notes-tests--note-fields 2)))))))

(ert-deftest agent-shell-notes-edit-mode-note-keys-inactive ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "ab")  ; id 1
      (agent-shell-notes-tests--capture buf 4 nil "cd")  ; id 2
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (agent-shell-notes-tests--key "C-x C-q")
        (dolist (key '("n" "p" "g" "q" "k" "e" "m" "u" "t" "U" "D"))
          (should-not (lookup-key (current-local-map) (kbd key))))
        ;; No map reaches the mark commands (DESIGN §5.3).
        (goto-char (point-min))
        (dolist (key '("m" "u" "t" "U"))
          (should-not (memq (key-binding (kbd key))
                            '(agent-shell-notes-mark
                              agent-shell-notes-unmark
                              agent-shell-notes-toggle-marks
                              agent-shell-notes-unmark-all))))
        ;; The keys that entered edit mode leave it, saving, as in wdired.
        (dolist (key '("C-x C-q" "C-c C-e"))
          (should (eq 'agent-shell-notes-edit-commit
                      (key-binding (kbd key)))))
        ;; In a note text, note keys type themselves.
        (goto-char (agent-shell-notes-tests--search "^ab$"))
        (agent-shell-notes-tests--type "nkq")
        (should (equal "nkqab" (buffer-substring-no-properties
                                (line-beginning-position) (line-end-position))))
        (should (= 2 (length agent-shell-notes--notes)))
        (should agent-shell-notes-edit-mode)))))

(ert-deftest agent-shell-notes-edit-mode-survives-a-capture ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 2 nil "ab")  ; id 1
      (agent-shell-notes-review)
      (let ((review (current-buffer)))
        (agent-shell-notes-tests--key "C-x C-q")
        (goto-char (agent-shell-notes-tests--search "^ab$"))
        (agent-shell-notes-tests--type "x")
        (agent-shell-notes-tests--capture buf 4 nil "cd")  ; id 2
        (with-current-buffer review
          (should agent-shell-notes-edit-mode)
          (should (agent-shell-notes-tests--search "^xab$"))
          (agent-shell-notes-tests--edit-key "C-c C-c")
          (should (equal "xab" (agent-shell-notes-tests--note-text 1)))
          ;; Leaving edit mode draws the note captured meanwhile.
          (should (equal '(1 2) (agent-shell-notes-tests--runs
                                 'agent-shell-notes-id))))))))

(ert-deftest agent-shell-notes-delete-note-at-point-without-asking ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5))))
      (agent-shell-notes-tests--capture buf 1 nil "one")    ; id 1
      (agent-shell-notes-tests--capture buf 3 nil "three")  ; id 2
      (agent-shell-notes-tests--capture buf 5 nil "five")   ; id 3
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should-error (progn (goto-char (point-min))
                             (agent-shell-notes-tests--key "k"))
                      :type 'user-error)
        (should (= 3 (length agent-shell-notes--notes)))
        (goto-char (1+ (agent-shell-notes-tests--note-pos 2)))
        (agent-shell-notes-tests--key "m")
        (goto-char (1+ (agent-shell-notes-tests--note-pos 2)))
        (cl-letf (((symbol-function 'y-or-n-p)
                   (lambda (&rest _) (error "Asked")))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (&rest _) (error "Asked"))))
          (agent-shell-notes-tests--key "k"))
        (should (equal '(1 3) (mapcar (lambda (note) (alist-get :id note))
                                      agent-shell-notes--notes)))
        (should (equal '(1 3) (agent-shell-notes-tests--runs
                               'agent-shell-notes-id)))
        ;; A deleted note leaves no stale mark.
        (should-not agent-shell-notes--marks)))))

;;;; The request

(defun agent-shell-notes-tests--request-start ()
  "Return the start of the request body in the review."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^# Request\n\n")
    (point)))

(defun agent-shell-notes-tests--request ()
  "Return the request body of the review, without properties."
  (buffer-substring-no-properties (agent-shell-notes-tests--request-start)
                                  (point-max)))

(ert-deftest agent-shell-notes-review-request-body-takes-typing ()
  (agent-shell-notes-tests--with-clean-state
    (agent-shell-notes-tests--review-with 2)
    (let ((start (agent-shell-notes-tests--request-start)))
      ;; The request is the last section, after the notes.
      (should (> start (agent-shell-notes-tests--note-pos 2)))
      (should (equal "" (agent-shell-notes-tests--request)))
      (goto-char start)
      (should (eq 'self-insert-command (key-binding "m")))
      (agent-shell-notes-tests--type "mn")
      ;; The first typed character carries the request keymap on.
      (should (eq 'self-insert-command (key-binding "m")))
      (agent-shell-notes-tests--type "m")
      (should (equal "mnm" (agent-shell-notes-tests--request)))
      (should (equal '(1 2) (mapcar (lambda (note) (alist-get :id note))
                                    agent-shell-notes--notes)))
      (should-not agent-shell-notes--marks)
      ;; Everything before the body stays read-only.
      (should-not (agent-shell-notes-tests--writable-p (1- start)))
      (should-not (agent-shell-notes-tests--writable-p
                   (- start (length "# Request\n\n"))))
      (should-not (agent-shell-notes-tests--writable-p (point-min)))
      ;; On a note the letters are note commands.
      (agent-shell-notes-tests--goto-note 1)
      (should (eq 'agent-shell-notes-mark (key-binding "m"))))))

(ert-deftest agent-shell-notes-review-request-survives-redraws ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--review-with 1)))
      (goto-char (agent-shell-notes-tests--request-start))
      (agent-shell-notes-tests--type "fix it")
      (agent-shell-notes-tests--key "g")
      (should (equal "fix it" (agent-shell-notes-tests--request)))
      (agent-shell-notes-tests--capture buf 2 nil "two")
      (set-buffer "*agent-shell-notes*")
      (should (equal "fix it" (agent-shell-notes-tests--request)))
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "C-x C-q")
      (should (equal "fix it" (agent-shell-notes-tests--request)))
      ;; Still writable in edit mode.
      (should (agent-shell-notes-tests--writable-p (point-max)))
      (agent-shell-notes-tests--edit-key "C-c C-k")
      (should (equal "fix it" (agent-shell-notes-tests--request)))
      (goto-char (point-max))
      (should (eq 'self-insert-command (key-binding "m"))))))

;;;; Rendering

(defconst agent-shell-notes-tests--golden-dir
  (expand-file-name "golden/"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory of the golden render files.")

(defun agent-shell-notes-tests--golden (name)
  "Return golden file NAME's text without its final newline."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat name ".txt") agent-shell-notes-tests--golden-dir))
    (string-remove-suffix "\n" (buffer-string))))

(defun agent-shell-notes-tests--file-note (id project file start end quote text)
  "Return a `file' note ID for FILE (relative to PROJECT), lines START-END."
  `((:id . ,id) (:source . file) (:project . ,project)
    (:location . (:file ,(concat project file) :start ,start :end ,end))
    (:quote . ,quote) (:text . ,text) (:markers . nil) (:archived . nil)
    (:created . nil)))

(ert-deftest agent-shell-notes-render-claude-file-notes ()
  (should (equal (agent-shell-notes-tests--golden "claude-file")
                 (agent-shell-notes--render
                  (list (agent-shell-notes-tests--file-note
                         1 "/proj/a/" "src/foo.el" 3 3
                         "(let ((cache (make-hash-table)))" "hoist the cache")
                        (agent-shell-notes-tests--file-note
                         2 "/proj/a/" "src/foo.el" 10 11
                         "  (puthash key value cache)  \n  cache)\t" ""))
                  "\n fix both, then run make check \n\n"
                  "/proj/a/"))))

(ert-deftest agent-shell-notes-render-claude-request-only ()
  (should (equal (agent-shell-notes-tests--golden "claude-request-only")
                 (agent-shell-notes--render
                  nil "fix both, then run make check" "/proj/a/"))))

(ert-deftest agent-shell-notes-render-claude-notes-only ()
  (should (equal "In `foo.el` at line 3:\n```elisp\nx\n```\nhere"
                 (agent-shell-notes--render
                  (list (agent-shell-notes-tests--file-note
                         1 "/proj/a/" "foo.el" 3 3 "x" "here"))
                  "  \n" "/proj/a/"))))

(ert-deftest agent-shell-notes-render-claude-cross-project ()
  (let ((notes (list (agent-shell-notes-tests--file-note
                      1 "/proj/a/" "src/foo.el" 3 3 "x" "here"))))
    (should (equal (agent-shell-notes-tests--golden "claude-cross-project")
                   (agent-shell-notes--render notes "" "/proj/b/")))
    ;; Same project, spelled without the slash: relative.
    (should (string-prefix-p "In `src/foo.el`"
                             (agent-shell-notes--render notes "" "/proj/a")))
    ;; No target (copy): relative.
    (should (string-prefix-p "In `src/foo.el`"
                             (agent-shell-notes--render notes "" nil)))))

(ert-deftest agent-shell-notes-render-claude-sanitizes-path-and-snippet ()
  (should (equal (agent-shell-notes-tests--golden "claude-sanitize")
                 (agent-shell-notes--render
                  (list (agent-shell-notes-tests--file-note
                         1 "/proj/a/" "src/we`ird\nname/@scope/a@b.zzz" 1 6
                         (concat "In foo at line 3 bar\n"
                                 "  Reply from x:\n"
                                 "<!-- attach me\n"
                                 "mail a@b.com\n"
                                 "cc @bill\n"
                                 "Inside at nothing")
                         "odd path"))
                  "" "/proj/a/"))))

(ert-deftest agent-shell-notes-render-claude-fence-outgrows-backticks ()
  (should (equal (agent-shell-notes-tests--golden "claude-fence")
                 (agent-shell-notes--render
                  (list (agent-shell-notes-tests--file-note
                         1 "/proj/a/" "README.md" 1 3 "see\n````\nx" ""))
                  "" "/proj/a/"))))

(ert-deftest agent-shell-notes-render-fence-language ()
  (let ((auto-mode-alist '(("\\.zig\\'" . zig-ts-mode)
                           ("\\.mk\\'" . makefile-gmake-mode)
                           ("\\.weird\\'" . (lambda () nil)))))
    (should (equal "elisp" (agent-shell-notes--fence-language "/a/b.el")))
    (should (equal "typescript" (agent-shell-notes--fence-language "/a/b.ts")))
    (should (equal "zig" (agent-shell-notes--fence-language "/a/b.zig")))
    (should (equal "makefile-gmake" (agent-shell-notes--fence-language "/a/b.mk")))
    (should (equal "text" (agent-shell-notes--fence-language "/a/b.weird")))
    (should (equal "text" (agent-shell-notes--fence-language "/a/Nofile")))))

;;;; Send and copy

(defun agent-shell-notes-tests--shell (name dir &optional session-id)
  "Return a fake shell buffer NAME in DIR, with SESSION-ID if non-nil.
Only the process boundary is stubbed, so a buffer with a state and a
directory is all the client reads."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer
      (setq default-directory dir)
      (setq-local agent-shell--state
                  (list (cons :session (list (cons :id session-id))))))
    (push buffer agent-shell-notes-tests--shells)
    buffer))

(defvar agent-shell-notes-tests--picked nil
  "The :buffers and :prompt of each picker call, newest first.")

(defvar agent-shell-notes-tests--sent nil
  "Each (BUFFER PROMPT DISPOSITION) the prompt-send stub got, newest first.")

(defmacro agent-shell-notes-tests--with-boundary (shells pick send &rest body)
  "Run BODY with the agent-shell process boundary stubbed.
SHELLS is what `agent-shell-buffers' returns.  PICK is called with the
picker's buffer list and returns the pick.  SEND is called after the
prompt-send call is recorded, with no arguments."
  (declare (indent 3) (debug t))
  `(let ((agent-shell-notes-tests--picked nil)
         (agent-shell-notes-tests--sent nil)
         (shells-fn (lambda () ,shells))
         (pick-fn ,pick)
         (send-fn ,send))
     (cl-letf (((symbol-function 'agent-shell-buffers) shells-fn)
               ((symbol-function 'agent-shell--read-shell-buffer)
                (cl-function
                 (lambda (&key prompt buffers &allow-other-keys)
                   (push (list buffers prompt) agent-shell-notes-tests--picked)
                   (funcall pick-fn buffers))))
               ((symbol-function 'agent-shell--prompt-send)
                (cl-function
                 (lambda (&key prompt disposition &allow-other-keys)
                   (push (list (current-buffer) prompt disposition)
                         agent-shell-notes-tests--sent)
                   (funcall send-fn)))))
       ,@body)))

(defun agent-shell-notes-tests--expected (dir &rest ids-and-request)
  "Return the claude text for one-line notes IDS of the review fixture.
Note I is line I of sample.el with text nI.  A string in
IDS-AND-REQUEST is the request."
  (ignore dir)
  (let ((request (seq-find #'stringp ids-and-request))
        (blocks (mapconcat
                 (lambda (i)
                   (format "In `sample.el` at line %d:\n```elisp\nline %d\n```\nn%d"
                           i i i))
                 (seq-remove #'stringp ids-and-request) "\n\n")))
    (if request (concat blocks "\n\n\n" request) blocks)))

(defun agent-shell-notes-tests--review-state ()
  "Return the notes, marks and request, to compare before and after."
  (list (copy-tree agent-shell-notes--notes)
        (copy-sequence agent-shell-notes--marks)
        (agent-shell-notes--request-text)))

(ert-deftest agent-shell-notes-send-marked-notes-and-request ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (agent-shell-notes-agent-shell-disposition 'queue))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--goto-note 3)
        (agent-shell-notes-tests--key "m")
        (agent-shell-notes-tests--goto-note 1)
        (agent-shell-notes-tests--key "m")
        (goto-char (point-max))
        (agent-shell-notes-tests--type "fix both")
        ;; C-c C-c from the request body sends too.
        (agent-shell-notes-tests--edit-key "C-c C-c")
        (should (equal "Send notes to: "
                       (nth 1 (car agent-shell-notes-tests--picked))))
        (should (equal (list (list shell
                                   (agent-shell-notes-tests--expected
                                    dir 1 3 "fix both")
                                   'queue))
                       agent-shell-notes-tests--sent))))))

(ert-deftest agent-shell-notes-send-note-at-point-without-marks ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1")))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (goto-char (1+ (agent-shell-notes-tests--note-pos 2)))
        (agent-shell-notes-tests--key "C-c C-c")
        (should (equal (agent-shell-notes-tests--expected dir 2)
                       (nth 1 (car agent-shell-notes-tests--sent))))
        ;; A mark left by a deleted note is ignored.
        (setq agent-shell-notes--marks '(99 3))
        (agent-shell-notes-tests--key "C-c C-c")
        (should (equal (agent-shell-notes-tests--expected dir 3)
                       (nth 1 (car agent-shell-notes-tests--sent))))
        ;; No marks, point in the request: nothing to send.
        (setq agent-shell-notes--marks nil)
        (goto-char (point-max))
        (should (equal "No note at point"
                       (cadr (should-error (agent-shell-notes-send)
                                           :type 'user-error))))
        (should (= 2 (length agent-shell-notes-tests--sent)))))))

(ert-deftest agent-shell-notes-send-picker-order ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 1))
           (dir (buffer-local-value 'default-directory src))
           (other (file-name-as-directory (make-temp-file "asn-other-" t)))
           (a (agent-shell-notes-tests--shell "A" other "sa"))
           (b (agent-shell-notes-tests--shell
               "B" (directory-file-name dir) "sb"))
           (c (agent-shell-notes-tests--shell "C" other "sc"))
           (d (agent-shell-notes-tests--shell "D" dir "sd"))
           ;; The same note goes twice.
           (agent-shell-notes-after-send 'keep))
      (agent-shell-notes-tests--with-boundary (list a b c d)
          (lambda (buffers) (car (last buffers))) #'ignore
        (agent-shell-notes-tests--goto-note 1)
        (agent-shell-notes-tests--key "C-c C-c")
        ;; Matching projects first, then the rest, each most recent first.
        (should (equal (list b d a c)
                       (car (car agent-shell-notes-tests--picked))))
        (should (eq c (car (car agent-shell-notes-tests--sent))))
        ;; The last target leads next time.
        (agent-shell-notes-tests--key "C-c C-c")
        (should (equal (list c b d a)
                       (car (car agent-shell-notes-tests--picked))))
        ;; Another project's target gets absolute paths.
        (should (string-prefix-p
                 (format "In `%ssample.el`" dir)
                 (nth 1 (car agent-shell-notes-tests--sent))))))))

(ert-deftest agent-shell-notes-send-refusals-leave-the-review ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (starting (agent-shell-notes-tests--shell "Starting" dir nil))
           (live (agent-shell-notes-tests--shell "Live" dir "s1")))
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "m")
      (goto-char (point-max))
      (agent-shell-notes-tests--type "go")
      (let ((before (agent-shell-notes-tests--review-state)))
        ;; No live shell: refused before the picker.
        (agent-shell-notes-tests--with-boundary nil #'car #'ignore
          (should (equal "No agent-shell session"
                         (cadr (should-error (agent-shell-notes-send)
                                             :type 'user-error))))
          (should-not agent-shell-notes-tests--picked))
        ;; A shell whose agent has not started: refused before sending.
        (agent-shell-notes-tests--with-boundary (list starting) #'car #'ignore
          (should-error (agent-shell-notes-send) :type 'user-error)
          (should-not agent-shell-notes-tests--sent))
        ;; The send seam fails: the error goes up, nothing changes.
        (agent-shell-notes-tests--with-boundary (list live) #'car
            (lambda () (user-error "This agent does not support steering"))
          (should (equal "This agent does not support steering"
                         (cadr (should-error (agent-shell-notes-send)
                                             :type 'user-error))))
          (should (= 1 (length agent-shell-notes-tests--sent))))
        (should (equal before (agent-shell-notes-tests--review-state)))
        (should-not agent-shell-notes--last-target)))))

(ert-deftest agent-shell-notes-copy-changes-nothing ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src)))
      (agent-shell-notes-tests--goto-note 2)
      (agent-shell-notes-tests--key "m")
      (agent-shell-notes-tests--key "m")
      (goto-char (point-max))
      (agent-shell-notes-tests--type "go")
      (let ((before (agent-shell-notes-tests--review-state)))
        (agent-shell-notes-tests--with-boundary nil #'car #'ignore
          (agent-shell-notes-tests--goto-note 1)
          ;; Batch has no echo area; `message' returns what it shows.
          (should (equal "Copied 2 notes"
                         (agent-shell-notes-tests--key "w")))
          (should (equal (agent-shell-notes-tests--expected dir 2 3 "go")
                         (car kill-ring)))
          (should-not agent-shell-notes-tests--picked)
          (should-not agent-shell-notes-tests--sent))
        (should (equal before (agent-shell-notes-tests--review-state)))
        ;; In the request body `w' types.
        (goto-char (point-max))
        (should (eq 'self-insert-command (key-binding "w")))))))

(ert-deftest agent-shell-notes-agent-shell-client-slots ()
  (agent-shell-notes-tests--with-clean-state
    (let ((shell (agent-shell-notes-tests--shell "Claude Agent @ x" "/tmp/" "s1"))
          (client agent-shell-notes-agent-shell-client))
      (should (eq client agent-shell-notes-client))
      (should (equal "Claude Agent @ x"
                     (funcall (plist-get client :name) shell)))
      (should (equal "s1" (funcall (plist-get client :session-id) shell)))
      (should (equal "/tmp/" (funcall (plist-get client :project) shell)))
      (should (eql 0 (funcall (plist-get client :turn-count) shell)))
      (dolist (slot '(:read-session :send :compose))
        (should (functionp (plist-get client slot)))))))

;;;; After send

(defun agent-shell-notes-tests--ids ()
  "Return the ids of the note list, in list order."
  (mapcar (lambda (note) (alist-get :id note)) agent-shell-notes--notes))

(defun agent-shell-notes-tests--send-marked (shell ids &optional request)
  "Mark IDS in the review, type REQUEST, and send them to SHELL.
The boundary must be stubbed by the caller."
  (agent-shell-notes-tests--key "U")
  (dolist (id ids)
    (agent-shell-notes-tests--goto-note id)
    (agent-shell-notes-tests--key "m"))
  (when request
    (goto-char (point-max))
    (agent-shell-notes-tests--type request))
  (agent-shell-notes-tests--goto-note (car ids))
  (agent-shell-notes-tests--key "C-c C-c")
  (should (eq shell (car (car agent-shell-notes-tests--sent)))))

(ert-deftest agent-shell-notes-after-send-remove-clears-marks-and-request ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 4))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1")))
      (should (eq 'remove agent-shell-notes-after-send))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(1 3) "fix both")
        (should (equal '(2 4) (agent-shell-notes-tests--ids)))
        (should (equal '(2 4) (agent-shell-notes-tests--runs
                               'agent-shell-notes-id)))
        (should-not agent-shell-notes--marks)
        (should (equal "" (agent-shell-notes-tests--request)))))))

;; Faces of the overlays over review note ID.
(defun agent-shell-notes-tests--overlay-faces (id)
  (let ((beg (agent-shell-notes-tests--note-pos id)))
    (delq nil (mapcar (lambda (ov) (overlay-get ov 'face))
                      (overlays-at (1+ beg))))))

(defun agent-shell-notes-tests--archived (id)
  (alist-get :archived (seq-find (lambda (note) (eql id (alist-get :id note)))
                                 agent-shell-notes--notes)))

(ert-deftest agent-shell-notes-after-send-archive-tags-and-dims ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (x (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (y (agent-shell-notes-tests--shell "Claude Agent @ y" dir "s2"))
           (target x))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _) "archive")))
        (call-interactively #'agent-shell-notes-set-after-send))
      (should (eq 'archive agent-shell-notes-after-send))
      (agent-shell-notes-tests--with-boundary (list x y)
          (lambda (_) target) #'ignore
        (agent-shell-notes-tests--send-marked x '(1 3) "go")
        (should (equal '(1 2 3) (agent-shell-notes-tests--ids)))
        (should (equal '(1 2 3) (agent-shell-notes-tests--runs
                                 'agent-shell-notes-id)))
        (should (equal "Claude Agent @ x" (agent-shell-notes-tests--archived 1)))
        (should-not (agent-shell-notes-tests--archived 2))
        (should (equal "**line 1** `sent to Claude Agent @ x`"
                       (agent-shell-notes-tests--field-text 1 'location)))
        (should (equal "**line 2**"
                       (agent-shell-notes-tests--field-text 2 'location)))
        (should (memq 'agent-shell-notes-archived
                      (agent-shell-notes-tests--overlay-faces 1)))
        (should-not (memq 'agent-shell-notes-archived
                          (agent-shell-notes-tests--overlay-faces 2)))
        (should-not agent-shell-notes--marks)
        (should (equal "" (agent-shell-notes-tests--request)))
        ;; Resending an archived note updates its tag.
        (setq target y)
        (agent-shell-notes-tests--send-marked y '(1))
        (should (equal "Claude Agent @ y" (agent-shell-notes-tests--archived 1)))
        (should (equal "**line 1** `sent to Claude Agent @ y`"
                       (agent-shell-notes-tests--field-text 1 'location)))
        (should (equal "Claude Agent @ x"
                       (agent-shell-notes-tests--archived 3)))))))

(ert-deftest agent-shell-notes-after-send-keep-leaves-notes ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (agent-shell-notes-after-send 'keep))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(2) "go")
        (should (equal '(1 2) (agent-shell-notes-tests--ids)))
        (should-not (agent-shell-notes-tests--archived 2))
        (should-not agent-shell-notes--marks)
        (should (equal "" (agent-shell-notes-tests--request)))))))

(ert-deftest agent-shell-notes-x-purges-archived-without-asking ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (agent-shell-notes-after-send 'archive))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(1 3)))
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "m")
      (agent-shell-notes-tests--goto-note 2)
      (agent-shell-notes-tests--key "m")
      (cl-letf (((symbol-function 'yes-or-no-p)
                 (lambda (_) (error "Asked")))
                ((symbol-function 'y-or-n-p)
                 (lambda (_) (error "Asked"))))
        (agent-shell-notes-tests--key "x"))
      (should (equal '(2) (agent-shell-notes-tests--ids)))
      (should (equal '(2) (agent-shell-notes-tests--runs
                           'agent-shell-notes-id)))
      (should (equal '(2) agent-shell-notes--marks))
      ;; Nothing archived: harmless.
      (agent-shell-notes-tests--key "x")
      (should (equal '(2) (agent-shell-notes-tests--ids))))))

(defun agent-shell-notes-tests--sorted-marks ()
  (sort (copy-sequence agent-shell-notes--marks) #'<))

(ert-deftest agent-shell-notes-restore-last-after-remove ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 4))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1")))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(1 3) "fix both"))
      (agent-shell-notes-tests--capture src 2 nil "five")
      (set-buffer "*agent-shell-notes*")
      (should (equal '(2 4 5) (agent-shell-notes-tests--ids)))
      (agent-shell-notes-tests--key "C-c C-r")
      ;; Back in their places; the later capture stays where it was.
      (should (equal '(1 2 3 4 5) (agent-shell-notes-tests--ids)))
      (should (equal '(1 2 5 3 4) (agent-shell-notes-tests--runs
                                   'agent-shell-notes-id)))
      (should (equal '(1 3) (agent-shell-notes-tests--sorted-marks)))
      (should (equal '(1 3) (agent-shell-notes-tests--marked)))
      (should (equal "fix both" (agent-shell-notes-tests--request)))
      ;; One level only.
      (should-error (agent-shell-notes-tests--key "C-c C-r")
                    :type 'user-error)
      (should (equal '(1 2 3 4 5) (agent-shell-notes-tests--ids))))))

(ert-deftest agent-shell-notes-restore-last-after-archive ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (x (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (y (agent-shell-notes-tests--shell "Claude Agent @ y" dir "s2"))
           (target x)
           (agent-shell-notes-after-send 'archive))
      (agent-shell-notes-tests--with-boundary (list x y)
          (lambda (_) target) #'ignore
        (agent-shell-notes-tests--send-marked x '(1))
        (setq target y)
        (agent-shell-notes-tests--send-marked y '(1 2) "again"))
      (should (equal "Claude Agent @ y" (agent-shell-notes-tests--archived 1)))
      ;; Restore is a global command too.
      (with-temp-buffer
        (agent-shell-notes-restore-last))
      (should (equal "Claude Agent @ x" (agent-shell-notes-tests--archived 1)))
      (should-not (agent-shell-notes-tests--archived 2))
      (should (equal '(1 2 3) (agent-shell-notes-tests--ids)))
      (should (equal '(1 2) (agent-shell-notes-tests--sorted-marks)))
      (should (equal "again" (agent-shell-notes-tests--request)))
      (should (equal "**line 1** `sent to Claude Agent @ x`"
                     (agent-shell-notes-tests--field-text 1 'location)))
      (should (equal "**line 2**"
                     (agent-shell-notes-tests--field-text 2 'location))))))

(ert-deftest agent-shell-notes-restore-last-after-keep ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1"))
           (agent-shell-notes-after-send 'keep))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(2) "go"))
      (agent-shell-notes-tests--key "C-c C-r")
      (should (equal '(1 2) (agent-shell-notes-tests--ids)))
      (should (equal '(2) agent-shell-notes--marks))
      (should (equal "go" (agent-shell-notes-tests--request))))))

(ert-deftest agent-shell-notes-failed-send-stores-nothing ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 3))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ x" dir "s1")))
      (should (equal "Nothing to restore"
                     (cadr (should-error (agent-shell-notes-restore-last)
                                         :type 'user-error))))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--send-marked shell '(1) "one"))
      (agent-shell-notes-tests--goto-note 2)
      (agent-shell-notes-tests--key "m")
      (goto-char (point-max))
      (agent-shell-notes-tests--type "two")
      (let ((before (agent-shell-notes-tests--review-state)))
        (agent-shell-notes-tests--with-boundary (list shell) #'car
            (lambda () (error "Session gone"))
          (should-error (agent-shell-notes-send)))
        (should (equal before (agent-shell-notes-tests--review-state))))
      ;; `w' stores nothing either.
      (agent-shell-notes-tests--key "w")
      ;; The store still holds the first send.
      (agent-shell-notes-tests--key "C-c C-r")
      (should (equal '(1 2 3) (agent-shell-notes-tests--ids)))
      (should (equal '(1) agent-shell-notes--marks))
      (should (equal "one" (agent-shell-notes-tests--request))))))

(ert-deftest agent-shell-notes-delete-marked-after-confirming ()
  (agent-shell-notes-tests--with-clean-state
    (let ((buf (agent-shell-notes-tests--file
                (agent-shell-notes-tests--lines 5)))
          prompts)
      (agent-shell-notes-tests--capture buf 1 nil "one")    ; id 1
      (agent-shell-notes-tests--capture buf 3 nil "three")  ; id 2
      (agent-shell-notes-tests--capture buf 5 nil "five")   ; id 3
      (agent-shell-notes-review)
      (with-current-buffer "*agent-shell-notes*"
        (should (equal "No marked notes"
                       (cadr (should-error (agent-shell-notes-tests--key "D")
                                           :type 'user-error))))
        (goto-char (1+ (agent-shell-notes-tests--note-pos 1)))
        (agent-shell-notes-tests--key "m")
        (goto-char (1+ (agent-shell-notes-tests--note-pos 3)))
        (agent-shell-notes-tests--key "m")
        ;; Declined: nothing changes.
        (cl-letf (((symbol-function 'yes-or-no-p)
                   (lambda (prompt) (push prompt prompts) nil)))
          (agent-shell-notes-tests--key "D"))
        (should (equal '("Delete 2 marked notes? ") prompts))
        (should (= 3 (length agent-shell-notes--notes)))
        (should (equal '(1 3) (sort (copy-sequence agent-shell-notes--marks)
                                    #'<)))
        ;; Confirmed: only the marked notes go, with their marks.
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) t)))
          (agent-shell-notes-tests--key "D"))
        (should (equal '(2) (mapcar (lambda (note) (alist-get :id note))
                                    agent-shell-notes--notes)))
        (should (equal '(2) (agent-shell-notes-tests--runs
                             'agent-shell-notes-id)))
        (should-not agent-shell-notes--marks)))))

;;;; Compose

(defmacro agent-shell-notes-tests--with-viewport (&rest body)
  "Run BODY with the real viewport code, stubbing only what needs a live shell.
The header and the turn position read a shell-maker shell."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'agent-shell-viewport--update-header) #'ignore)
             ((symbol-function 'agent-shell-viewport--position) #'ignore))
     ,@body))

(defun agent-shell-notes-tests--compose ()
  "Run `C-u C-c C-c' in the review."
  (let ((current-prefix-arg '(4)))
    (agent-shell-notes-tests--key "C-c C-c")))

(ert-deftest agent-shell-notes-compose-appends-after-the-draft ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ c" dir "s1"))
           (review (current-buffer)))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--with-viewport
          ;; Bill's draft, to be steered in.
          (let ((viewport (alist-get :buffer
                                     (agent-shell-viewport--show-buffer
                                      :append "my draft" :shell-buffer shell
                                      :edit t :disposition 'steer))))
            (select-window (display-buffer review))
            (set-buffer review)
            (agent-shell-notes-tests--goto-note 2)
            (agent-shell-notes-tests--compose)
            (should-not agent-shell-notes-tests--sent)
            (should (eq viewport (window-buffer (selected-window))))
            (with-current-buffer viewport
              (should (equal (concat "my draft\n\n"
                                     (agent-shell-notes-tests--expected dir 2))
                             (string-trim (buffer-string))))
              (should (eq 'steer agent-shell-viewport--compose-disposition)))
            (should (eq shell agent-shell-notes--last-target))))))))

(ert-deftest agent-shell-notes-compose-without-a-viewport ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ f" dir "s1"))
           (agent-shell-notes-agent-shell-disposition 'queue))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--with-viewport
          (agent-shell-notes-tests--goto-note 1)
          (agent-shell-notes-tests--key "m")
          (goto-char (point-max))
          (agent-shell-notes-tests--type "go")
          ;; From the request body, as `C-c C-c' sends from there.
          (let ((current-prefix-arg '(4)))
            (agent-shell-notes-tests--edit-key "C-c C-c"))
          (should-not agent-shell-notes-tests--sent)
          (let ((viewport (window-buffer (selected-window))))
            (should (equal (concat (buffer-name shell) " [viewport]")
                           (buffer-name viewport)))
            (with-current-buffer viewport
              (should (derived-mode-p 'agent-shell-viewport-edit-mode))
              (should (equal (agent-shell-notes-tests--expected dir 1 "go")
                             (string-trim (buffer-string))))
              ;; Nothing to keep: the send disposition does not apply.
              (should-not agent-shell-viewport--compose-disposition))))))))

(ert-deftest agent-shell-notes-compose-needs-a-compose-client ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ n" dir "s1"))
           (agent-shell-notes-client
            (map-delete (copy-sequence agent-shell-notes-agent-shell-client)
                        :compose)))
      (should-not (plist-member agent-shell-notes-client :compose))
      (agent-shell-notes-tests--goto-note 1)
      (agent-shell-notes-tests--key "m")
      (goto-char (point-max))
      (agent-shell-notes-tests--type "go")
      (agent-shell-notes-tests--goto-note 2)
      (let ((before (agent-shell-notes-tests--review-state)))
        (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
          (agent-shell-notes-tests--with-viewport
            (let ((message (cadr (should-error
                                  (agent-shell-notes-tests--compose)
                                  :type 'user-error))))
              (should (string-prefix-p "Client (:read-session " message))
              (should (string-suffix-p " cannot fill a compose buffer"
                                       message)))
            (should-not agent-shell-notes-tests--picked)
            (should-not agent-shell-notes-tests--sent)))
        (should (equal before (agent-shell-notes-tests--review-state)))
        (should-not agent-shell-notes--last-target)
        (should-not (get-buffer (concat (buffer-name shell) " [viewport]")))))))

(ert-deftest agent-shell-notes-compose-applies-after-send-and-restore ()
  (agent-shell-notes-tests--with-clean-state
    (let* ((src (agent-shell-notes-tests--review-with 2))
           (dir (buffer-local-value 'default-directory src))
           (shell (agent-shell-notes-tests--shell "Claude Agent @ r" dir "s1"))
           (review (current-buffer))
           (agent-shell-notes-after-send 'archive))
      (agent-shell-notes-tests--with-boundary (list shell) #'car #'ignore
        (agent-shell-notes-tests--with-viewport
          (agent-shell-notes-tests--goto-note 1)
          (agent-shell-notes-tests--key "m")
          (goto-char (point-max))
          (agent-shell-notes-tests--type "go")
          (agent-shell-notes-tests--goto-note 1)
          (agent-shell-notes-tests--compose)
          (should-not agent-shell-notes-tests--sent)
          (should (equal "Claude Agent @ r"
                         (agent-shell-notes-tests--archived 1)))
          (should-not agent-shell-notes--marks)
          (with-current-buffer review
            (should (equal "" (agent-shell-notes-tests--request)))
            (should (equal "**line 1** `sent to Claude Agent @ r`"
                           (agent-shell-notes-tests--field-text 1 'location))))
          ;; Restore from the compose buffer, as a global command.
          (agent-shell-notes-restore-last)
          (should-not (agent-shell-notes-tests--archived 1))
          (should (equal '(1) agent-shell-notes--marks))
          (with-current-buffer review
            (should (equal "go" (agent-shell-notes-tests--request)))))))))

(provide 'agent-shell-notes-tests)
;;; agent-shell-notes-tests.el ends here
