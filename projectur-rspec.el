(require 'projectur)

(define-compilation-mode rspec-mode "Rspec" "Mode for executing Rspec specs.")

(setq rspec-scroll-output t)

(add-hook 'rspec-start-hook (lambda () (goto-char (point-max))))
(add-hook 'rspec-filter-hook
          (defun rspec-colorize-buffer ()
            (let ((inhibit-read-only t))
              (ansi-color-apply-on-region (point-min) (point-max)))))

;;;###autoload
(defun projectur-rspec (&optional arg)
  "Without prefix argument executes spec found at current point position.
With single prefix argument executes all spec found in current file.
With double prefix argument executes whole rspec suite of current project."
  (interactive "p")
  (let ((scope
         (cond
           ((eq arg 1) 'at-point)
           ((eq arg 4) 'file)
           ((eq arg 16) 'suite))))
    (projectur-rspec-sanity-check scope)
    (projectur-rspec-execute-specs scope)))

(defun projectur-rspec-sanity-check (scope)
  "Check if current location is appropriate for running specs within SCOPE."
  (when (memq scope '(at-point file))
    (unless (and
             buffer-file-name
             (string-match-p "._spec\.rb" buffer-file-name))
      (error "Current buffer does not seem to be visiting RSpec spec file"))))

(defun projectur-rspec-execute-specs (scope)
  "Executes rspec examples selected according to SCOPE.
if SCOPE = 'at-point - example found at current point position.
if SCOPE = 'file - examples found in currently visited file.
if SCOPE = 'suite - whole rspec suite."
  (projectur-with-project (projectur-current-project)
    (let ((file (file-relative-name buffer-file-name default-directory))
          (line-number (line-number-at-pos))
          (command '("rspec")))

      (when (eq scope 'at-point)
        (add-to-list 'command "--line_number" 'append)
        (add-to-list 'command (number-to-string line-number) 'append))

      (unless (eq scope 'suite)
        (add-to-list 'command (shell-quote-argument file) 'append))

      (setq command (mapconcat 'identity command " "))

      (projectur-save)

      (compilation-start command 'rspec-mode))))

(provide 'projectur-rspec)
