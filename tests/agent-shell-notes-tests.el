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
         (agent-shell-notes--next-id 0))
     (unwind-protect
         (save-window-excursion
           (delete-other-windows)
           ,@body)
       (dolist (name '("*agent-shell-notes*" "*agent-shell-notes capture*"))
         (when (get-buffer name)
           (kill-buffer name))))))

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

(provide 'agent-shell-notes-tests)
;;; agent-shell-notes-tests.el ends here
