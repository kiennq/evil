;;; evil-benchmark-runtime.el --- Runtime editing benchmarks for Evil -*- lexical-binding: t; -*-

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Batch benchmark harness focused on runtime editing scenarios.
;;
;; Usage:
;;   emacs -Q --batch -L . -l scripts/evil-benchmark-runtime.el

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'elp)

(add-to-list 'load-path default-directory)

(require 'evil)

(setq load-prefer-newer nil
      message-log-max nil)

(defvar evil-bench-run-on-load t
  "Whether `evil-bench-run' should execute when this file is loaded.")

(defconst evil-bench--text-line
  "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega\n")

(defconst evil-bench--motion-macro
  (kbd "wwwwbbbbjjkkllhh0$"))

(defconst evil-bench--large-file-cursor-motion-macro
  (kbd "150j80k0$^wwbbllhh"))

(defconst evil-bench--motion-with-state-changes-macro
  (kbd "20j15ki xyz<escape>0$ab<escape>ggG"))


(defconst evil-bench--delete-word-macro
  (kbd "dw"))

(defconst evil-bench--insert-macro
  (kbd "abc def ghi"))

(defconst evil-bench--elp-functions
  '(evil-change-state
    evil-initialize
    evil-initialize-local-keymaps
    evil-initialize-state
    evil-initial-state-for-buffer
    evil-initial-state
    evil-local-mode
    evil-line-move
    evil-normalize-keymaps
    evil-state-keymaps
    evil-state-auxiliary-keymaps
    evil-state-overriding-keymaps
    evil-state-intercept-keymaps
    evil-mode-for-keymap
    evil-keymap-for-mode
    evil-state-property
    evil-refresh-mode-line
    evil-refresh-cursor
    evil-adjust-cursor
    evil-move-cursor-back
    evil-move-to-column
    evil--repeat-type
    evil-get-command-property
    evil-repeat-start
    evil-repeat-stop
    evil-repeat-keystrokes
    evil-repeat-pre-hook
    evil-repeat-post-hook
    evil-cleanup-insert-state
    evil-execute-repeat-info))

(defun evil-bench--print-system-info ()
  (princ (format "SYSTEM|emacs=%s|system=%s|noninteractive=%S\n"
                 emacs-version system-type noninteractive)))

(defun evil-bench--make-buffer (&optional line-count)
  (let ((buffer (generate-new-buffer " *evil-bench*"))
        (line-count (or line-count 3000)))
    (with-current-buffer buffer
      (dotimes (_ line-count)
        (insert evil-bench--text-line))
      (goto-char (point-min))
      (fundamental-mode)
      (setq-local inhibit-message t)
      (evil-local-mode 1)
      (evil-normal-state))
    buffer))

(defmacro evil-bench--with-buffer (spec &rest body)
  "Execute BODY in a temporary benchmark buffer."
  (declare (indent 1) (debug (sexp body)))
  (let ((buffer (car spec))
        (line-count (cadr spec)))
    `(let ((,buffer (evil-bench--make-buffer ,line-count)))
       (unwind-protect
           (save-window-excursion
             (switch-to-buffer ,buffer)
             ,@body)
         (when (buffer-live-p ,buffer)
           (kill-buffer ,buffer))))))

(defun evil-bench--print-result (name repeats result)
  (pcase-let ((`(,elapsed ,gc-runs ,gc-elapsed) result))
    (princ (format "RESULT|%s|repeats=%d|elapsed=%.6f|gc-runs=%d|gc-elapsed=%.6f\n"
                   name repeats elapsed gc-runs gc-elapsed))))

(defmacro evil-bench--measure (name repeats &rest body)
  "Benchmark BODY REPEATS times and print a formatted result line."
  (declare (indent 2) (debug (sexp sexp body)))
  `(progn
     (garbage-collect)
     (evil-bench--print-result
      ,name ,repeats
      (benchmark-run ,repeats
        ,@body))))

(defun evil-bench-state-transitions (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "state-transitions" repeats
      (with-current-buffer buffer
        (evil-insert-state)
        (evil-normal-state)
        (evil-emacs-state)
        (evil-normal-state)
        (evil-operator-state)
        (evil-normal-state)))))

(defun evil-bench-motion-loop (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "motion-loop" repeats
      (with-current-buffer buffer
        (goto-char (point-min))
        (evil-normal-state)
        (execute-kbd-macro evil-bench--motion-macro)
        (when (> (line-number-at-pos) 2500)
          (goto-char (point-min)))))))

(defun evil-bench-delete-loop (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "delete-word-loop" repeats
      (with-current-buffer buffer
        (when (< (- (point-max) (point)) 16)
          (erase-buffer)
          (dotimes (_ 3000)
            (insert evil-bench--text-line))
          (goto-char (point-min))
          (evil-normal-state))
        (execute-kbd-macro evil-bench--delete-word-macro)))))

(defun evil-bench-insert-edit-loop (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "insert-edit-loop" repeats
      (with-current-buffer buffer
        (goto-char (point-min))
        (evil-insert-state)
        (execute-kbd-macro evil-bench--insert-macro)
        (evil-normal-state)))))

(defun evil-bench-local-mode-toggle (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "local-mode-toggle" repeats
      (with-current-buffer buffer
        (evil-local-mode -1)
        (evil-local-mode 1)
        (evil-normal-state)))))

(defun evil-bench-startup-local-enable (repeats)
  (evil-bench--measure "startup-local-enable" repeats
    (let ((buffer (generate-new-buffer " *evil-startup-bench*")))
      (unwind-protect
          (with-current-buffer buffer
            (fundamental-mode)
            (evil-local-mode 1))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(defun evil-bench-large-file-cursor-motion (repeats)
  (evil-bench--with-buffer (buffer 25000)
    (evil-bench--measure "large-file-cursor-motion" repeats
      (with-current-buffer buffer
        (goto-char (point-min))
        (forward-line 12000)
        (move-to-column 40)
        (evil-normal-state)
        (execute-kbd-macro evil-bench--large-file-cursor-motion-macro)
        (when (> (line-number-at-pos) 20000)
          (goto-char (point-min)))))))

(defun evil-bench-motion-with-state-changes (repeats)
  (evil-bench--with-buffer (buffer 25000)
    (evil-bench--measure "motion-with-state-changes" repeats
      (with-current-buffer buffer
        (goto-char (point-min))
        (forward-line 8000)
        (move-to-column 20)
        (evil-normal-state)
        (execute-kbd-macro evil-bench--motion-with-state-changes-macro)
        (when (> (line-number-at-pos) 20000)
          (goto-char (point-min)))))))

(defun evil-bench-window-configuration-churn (repeats)
  (evil-bench--with-buffer (buffer)
    (evil-bench--measure "window-configuration-churn" repeats
      (with-current-buffer buffer
        (delete-other-windows)
        (goto-char (point-min))
        (evil-normal-state)
        (evil-set-jump)
        (let ((new-window (split-window-right)))
          (other-window 1)
          (other-window -1)
          (delete-window new-window))))))


(defun evil-bench--run-elp-profile (name thunk)
  (dolist (fn evil-bench--elp-functions)
    (elp-instrument-function fn))
  (mapc #'elp-reset-function evil-bench--elp-functions)
  (unwind-protect
      (progn
        (funcall thunk)
        (princ (format "ELP-BEGIN|%s\n" name))
        (let ((elp-use-standard-output t)
              (elp-sort-by-function 'elp-sort-by-total-time))
          (elp-results))
        (princ (format "ELP-END|%s\n" name))
        t)
    (mapc #'elp-restore-function evil-bench--elp-functions)))

(defun evil-bench-profile-state-transitions ()
  (evil-bench--run-elp-profile
   "state-transitions"
   (lambda ()
     (evil-bench--with-buffer (buffer)
       (with-current-buffer buffer
         (dotimes (_ 2000)
           (evil-insert-state)
           (evil-normal-state)
           (evil-emacs-state)
           (evil-normal-state)))))))

(defun evil-bench-profile-insert-edit-loop ()
  (evil-bench--run-elp-profile
   "insert-edit-loop"
   (lambda ()
     (evil-bench--with-buffer (buffer)
       (with-current-buffer buffer
         (dotimes (_ 1200)
           (goto-char (point-min))
           (evil-insert-state)
           (execute-kbd-macro evil-bench--insert-macro)
           (evil-normal-state)))))))

(defun evil-bench-profile-large-file-cursor-motion ()
  (evil-bench--run-elp-profile
   "large-file-cursor-motion"
   (lambda ()
     (evil-bench--with-buffer (buffer 25000)
       (with-current-buffer buffer
         (goto-char (point-min))
         (forward-line 12000)
         (move-to-column 40)
          (evil-normal-state)
          (dotimes (_ 1500)
            (execute-kbd-macro evil-bench--large-file-cursor-motion-macro)))))))

(defun evil-bench-profile-startup-local-enable ()
  (evil-bench--run-elp-profile
   "startup-local-enable"
   (lambda ()
     (dotimes (_ 400)
       (let ((buffer (generate-new-buffer " *evil-startup-profile*")))
         (unwind-protect
             (with-current-buffer buffer
               (fundamental-mode)
               (evil-local-mode 1))
           (when (buffer-live-p buffer)
             (kill-buffer buffer))))))))

(defun evil-bench-run ()
  (evil-bench--print-system-info)
  (evil-bench-startup-local-enable 1200)
  (evil-bench-state-transitions 4000)
  (evil-bench-motion-loop 6000)
  (evil-bench-delete-loop 3000)
  (evil-bench-insert-edit-loop 2500)
  (evil-bench-local-mode-toggle 1200)
  (evil-bench-large-file-cursor-motion 1500)
  (evil-bench-motion-with-state-changes 1200)
  (evil-bench-window-configuration-churn 2000)
  (evil-bench-profile-startup-local-enable)
  (evil-bench-profile-state-transitions)
  (evil-bench-profile-insert-edit-loop)
  (evil-bench-profile-large-file-cursor-motion))

(when evil-bench-run-on-load
  (evil-bench-run))

;;; evil-benchmark-runtime.el ends here
