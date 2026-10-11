;;; agent-shell-notes-live.el --- Live round trip against a real agent -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: MIT
;; Copyright (C) 2026 Bill and contributors

;;; Commentary:

;; Drives agent-shell-notes against a real claude-agent-acp session
;; started through agent-shell.
;;
;; Run with `make live-check', never `make check'.  This starts an agent
;; and spends real API tokens.  It asserts only what the package hands to
;; agent-shell, never what the model answers:
;;
;; - a two-note review sent with `C-c C-c' reaches the agent as exactly
;;   the rendered `claude' text (the `input-submitted' prompt);
;; - `C-u' `agent-shell-notes-send-all' puts the same text in the real
;;   viewport compose buffer, after an existing draft.
;;
;; Permissions: reads are approved, everything else is rejected, so an
;; unattended run never lets the agent change anything.

;;; Code:

(require 'agent-shell)
(require 'agent-shell-anthropic)
(require 'agent-shell-notes)
(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)

(defvar agent-shell-notes-live-timeout 180
  "Seconds to wait for the agent's turn.")

(defvar agent-shell-notes-live-startup-timeout 120
  "Seconds to wait for the shell to have a session and a prompt.")

(defconst agent-shell-notes-live-request
  "This is a test of the transport only. Do not use any tools. Reply with just OK."
  "The request sent with the notes; keeps the turn short.")

(defvar agent-shell-notes-live--results nil
  "Outcomes, newest first, as (STATUS NAME DETAIL).")

;;; Reporting

(defun agent-shell-notes-live--check (name ok detail)
  "Record NAME as passed when OK, else failed, with DETAIL."
  (let ((status (if ok 'pass 'fail)))
    (push (list status name detail) agent-shell-notes-live--results)
    (princ (format "%-5s %s\n      %s\n" (upcase (symbol-name status))
                   name detail))
    ok))

(defun agent-shell-notes-live--report ()
  "Print the summary.  Return non-nil when nothing failed."
  (let ((failed (seq-filter (lambda (r) (eq (car r) 'fail))
                            agent-shell-notes-live--results)))
    (princ (format "\n%d passed, %d failed\n"
                   (- (length agent-shell-notes-live--results) (length failed))
                   (length failed)))
    (null failed)))

;;; Waiting

(defun agent-shell-notes-live--wait (predicate timeout)
  "Run the event loop until PREDICATE holds or TIMEOUT seconds pass."
  (let ((deadline (time-add (current-time) (seconds-to-time timeout))))
    (catch 'done
      (while (time-less-p (current-time) deadline)
        (when (funcall predicate)
          (throw 'done t))
        (accept-process-output nil 0.05))
      (funcall predicate))))

(defun agent-shell-notes-live--subscribe (shell event fn)
  "Call FN with each EVENT of SHELL; return the token."
  (agent-shell-subscribe-to :shell-buffer shell :event event :on-event fn))

(defun agent-shell-notes-live--unsubscribe (shell token)
  "Drop subscription TOKEN from SHELL."
  (when (and token (buffer-live-p shell))
    (with-current-buffer shell
      (ignore-errors (agent-shell-unsubscribe :subscription token)))))

;;; Permissions

(defun agent-shell-notes-live--responder (permission)
  "Allow PERMISSION when it only reads, reject it otherwise."
  (let* ((read (equal (map-elt (map-elt permission :tool-call) :kind) "read"))
         (kinds (if read '("allow_once") '("reject_once" "reject_always")))
         (choice (seq-find (lambda (option)
                             (member (map-elt option :kind) kinds))
                           (map-elt permission :options))))
    (when choice
      (funcall (map-elt permission :respond) (map-elt choice :option-id))
      t)))

;;; Fixture

(defun agent-shell-notes-live--source ()
  "Visit a three-line sample.el in a fresh directory; return its buffer."
  (let* ((dir (file-name-as-directory
               (make-temp-file "agent-shell-notes-live-" t)))
         (file (expand-file-name "sample.el" dir)))
    (with-temp-file file
      (insert "line 1\nline 2\nline 3\n"))
    (find-file-noselect file)))

(defun agent-shell-notes-live--capture (buffer line text)
  "Capture LINE of BUFFER with note TEXT through the popup."
  (switch-to-buffer buffer)
  (goto-char (point-min))
  (forward-line (1- line))
  (agent-shell-notes-capture)
  (with-current-buffer "*agent-shell-notes capture*"
    (goto-char (point-max))
    (insert text)
    (agent-shell-notes-capture-save)))

(defconst agent-shell-notes-live-expected
  (concat "In `sample.el` at line 1:\n```elisp\nline 1\n```\nn1\n\n"
          "In `sample.el` at line 3:\n```elisp\nline 3\n```\nn3\n\n\n"
          agent-shell-notes-live-request)
  "The `claude' text for notes 1 and 3 and the request, written by hand.")

(defun agent-shell-notes-live--start (source)
  "Start a Claude shell in SOURCE's directory; return it once it has a session."
  (let* ((ready nil)
         (shell (with-current-buffer source
                  (agent-shell--start
                   :config (agent-shell-anthropic-make-claude-code-config)
                   :no-focus t :new-session t :session-strategy 'new)))
         (token (agent-shell-notes-live--subscribe
                 shell 'prompt-ready (lambda (_) (setq ready t)))))
    (unwind-protect
        (unless (agent-shell-notes-live--wait
                 (lambda () (and ready (agent-shell-session-id
                                        :shell-buffer shell)))
                 agent-shell-notes-live-startup-timeout)
          (error "No session within %ss; shell buffer:\n%s"
                 agent-shell-notes-live-startup-timeout
                 (with-current-buffer shell (buffer-string))))
      (agent-shell-notes-live--unsubscribe shell token))
    shell))

(defun agent-shell-notes-live--kill (&rest buffers)
  "Kill BUFFERS, shutting down the agent behind a shell.
Killing a viewport from its selected window asks whether to kill its
shell too; batch has no one to answer, so the answer is yes."
  (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
    (dolist (buffer buffers)
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

;;; The round trip

(defun agent-shell-notes-live--round-trip ()
  "Send a two-note review, then compose with send-all after a draft."
  (let* ((source (agent-shell-notes-live--source))
         (shell nil)
         (viewport nil)
         (prompts nil)
         (done nil)
         (tokens nil)
         (agent-shell-notes-after-send 'keep))
    (unwind-protect
        (progn
          (setq shell (agent-shell-notes-live--start source))
          (push (agent-shell-notes-live--subscribe
                 shell 'input-submitted
                 (lambda (event)
                   (push (map-nested-elt event '(:data :prompt)) prompts)))
                tokens)
          (push (agent-shell-notes-live--subscribe
                 shell 'turn-complete (lambda (_) (setq done "arrived")))
                tokens)
          ;; An ACP error (an expired login, say) ends the turn too.
          (push (agent-shell-notes-live--subscribe
                 shell 'error
                 (lambda (event)
                   (setq done (format "error: %s"
                                      (map-nested-elt event
                                                      '(:data :message))))))
                tokens)
          (dolist (n '(1 2 3))
            (agent-shell-notes-live--capture source n (format "n%d" n)))
          ;; The review: mark notes 1 and 3, type the request, `C-c C-c'.
          (agent-shell-notes-review)
          (with-current-buffer "*agent-shell-notes*"
            (dolist (id '(1 3))
              (goto-char (text-property-any (point-min) (point-max)
                                            'agent-shell-notes-id id))
              (agent-shell-notes-mark))
            (goto-char (point-max))
            (insert agent-shell-notes-live-request)
            ;; The real picker reads the minibuffer; take the only shell.
            (cl-letf (((symbol-function 'agent-shell--read-shell-buffer)
                       (cl-function (lambda (&key buffers &allow-other-keys)
                                      (car buffers)))))
              (agent-shell-notes-send)))
          (agent-shell-notes-live--wait
           (lambda () done) agent-shell-notes-live-timeout)
          (agent-shell-notes-live--check
           "the transcript's user prompt is the rendered text"
           (equal (list agent-shell-notes-live-expected) prompts)
           (format "input-submitted prompts: %S" (reverse prompts)))
          ;; Whether the model answers is not under test; say what happened.
          (princ (format "INFO  turn end: %s\n"
                         (or done
                             (format "nothing within %ss"
                                     agent-shell-notes-live-timeout))))
          ;; Compose: a draft first, then `C-u' send-all of notes 1 and 3.
          (setq viewport (alist-get :buffer
                                    (agent-shell-viewport--show-buffer
                                     :append "my draft" :shell-buffer shell
                                     :edit t)))
          (with-current-buffer "*agent-shell-notes*"
            (goto-char (text-property-any (point-min) (point-max)
                                          'agent-shell-notes-id 2))
            (agent-shell-notes-delete)
            (goto-char (point-max))
            (insert agent-shell-notes-live-request))
          (cl-letf (((symbol-function 'agent-shell--read-shell-buffer)
                     (cl-function (lambda (&key buffers &allow-other-keys)
                                    (car buffers)))))
            (let ((current-prefix-arg '(4)))
              (call-interactively #'agent-shell-notes-send-all)))
          (let ((text (with-current-buffer viewport
                        (string-trim (buffer-substring-no-properties
                                      (point-min) (point-max))))))
            (agent-shell-notes-live--check
             "the compose buffer holds the text after the draft"
             (equal (concat "my draft\n\n" agent-shell-notes-live-expected)
                    text)
             (format "compose buffer: %S" text)))
          (agent-shell-notes-live--check
           "compose sent nothing" (= 1 (length prompts))
           (format "%d prompts submitted" (length prompts))))
      (dolist (token tokens)
        (agent-shell-notes-live--unsubscribe shell token))
      (agent-shell-notes-live--kill shell viewport source
                                    (get-buffer "*agent-shell-notes*")))))

;;; Runner

(defun agent-shell-notes-live-run ()
  "Run the live round trip and print a report.
Return non-nil when every check passed."
  (let ((agent-shell-notes-live--results nil)
        (agent-shell-permission-responder-function
         #'agent-shell-notes-live--responder))
    (unless (executable-find "claude-agent-acp")
      (error "The claude-agent-acp executable is not on PATH"))
    (condition-case err
        (agent-shell-notes-live--round-trip)
      (error
       (agent-shell-notes-live--check
        "the round trip ran" nil (error-message-string err))))
    (agent-shell-notes-live--report)))

(defun agent-shell-notes-live-batch ()
  "Run the live round trip and exit non-zero when a check failed."
  (kill-emacs (if (agent-shell-notes-live-run) 0 1)))

(provide 'agent-shell-notes-live)
;;; agent-shell-notes-live.el ends here
