# Evil Jumps Window-Parameter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `evil-jumps` per-window state to a window parameter and keep the change only if targeted tests and benchmarks show a real win.

**Architecture:** `evil--jumps-get-current` becomes the single point of truth for per-window jump state by storing an `evil-jumps-struct` in a window parameter. Window-configuration handling keeps jump inheritance behavior but drops global hash-table cleanup.

**Tech Stack:** Emacs Lisp, ERT, Evil benchmark harness, git

---

### Task 1: Add failing tests for parameter-backed storage

**Files:**
- Modify: `evil-tests.el`
- Test: `evil-tests.el`

- [ ] **Step 1: Write the failing test**

```elisp
(ert-deftest evil-test-jumps-store-state-in-window-parameter ()
  :tags '(evil jumps)
  (let ((window (selected-window)))
    (set-window-parameter window 'evil-jumps nil)
    (should (evil-jumps-struct-p
             (evil--jumps-get-current window)))
    (should (evil-jumps-struct-p
             (window-parameter window 'evil-jumps)))))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `emacs -Q --batch -L . --eval "(setq evil-tests-run nil)" -l evil-tests.el --eval "(evil-tests-run '(evil-test-jumps-store-state-in-window-parameter))"`
Expected: FAIL because the window parameter remains nil with the current hash-table implementation.

- [ ] **Step 3: Write the second failing test**

```elisp
(ert-deftest evil-test-jumps-split-window-does-not-share-state ()
  :tags '(evil jumps)
  (save-window-excursion
    (delete-other-windows)
    (let* ((evil--jumps-buffer-targets "\\*\\(new\\|scratch\\|test\\)\\*")
           (source (selected-window))
           source-struct target target-struct)
      (switch-to-buffer (get-buffer-create "*scratch*"))
      (with-selected-window source
        (evil-local-mode 1)
        (insert "alpha\nbravo\n")
        (goto-char (point-min))
        (evil--jumps-push)
        (setq source-struct (evil--jumps-get-current source)))
      (setq target (split-window-right))
      (evil--jumps-window-configuration-hook)
      (setq target-struct (evil--jumps-get-current target))
      (should (evil-jumps-struct-p target-struct))
      (should-not (eq source-struct target-struct))
      (should-not (eq (evil-jumps-struct-ring source-struct)
                      (evil-jumps-struct-ring target-struct))))))
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `emacs -Q --batch -L . --eval "(setq evil-tests-run nil)" -l evil-tests.el --eval "(evil-tests-run '(or evil-test-jumps-store-state-in-window-parameter evil-test-jumps-split-window-does-not-share-state))"`
Expected: FAIL due to missing parameter-backed storage.

### Task 2: Implement parameter-backed window storage

**Files:**
- Modify: `evil-jumps.el`

- [ ] **Step 1: Replace hash-table access in `evil--jumps-get-current`**

Implement:

```elisp
(let ((jump-struct (window-parameter window 'evil-jumps)))
  (unless jump-struct
    (setq jump-struct (make-evil-jumps-struct))
    (set-window-parameter window 'evil-jumps jump-struct))
  jump-struct)
```

- [ ] **Step 2: Remove dead-window cleanup and hash-table dependency**

Update `evil--jumps-window-configuration-hook` so it keeps copy-on-new-window behavior, detects or clears inherited shared parameter state on new split windows, and no longer calls `maphash` / `remhash`.

- [ ] **Step 3: Delete obsolete hash-table storage**

Remove `evil--jumps-window-jumps` and verify no production references remain.

- [ ] **Step 4: Run targeted tests to verify they pass**

Run: `emacs -Q --batch -L . --eval "(setq evil-tests-run nil)" -l evil-tests.el --eval "(evil-tests-run '(or evil-test-jumps-store-state-in-window-parameter evil-test-jumps-split-window-does-not-share-state))"`
Expected: PASS.

### Task 3: Add and use a dedicated window-churn benchmark

**Files:**
- Modify: `scripts/evil-benchmark-runtime.el`

- [ ] **Step 1: Write the benchmark helper**

Add a workload that repeatedly:

```elisp
(delete-other-windows)
(split-window-right)
(other-window 1)
(other-window -1)
(delete-window (next-window))
```

with Evil jump tracking active and at least one existing jump list.

- [ ] **Step 2: Run the benchmark on the current baseline**

Run: `emacs -Q --batch -L . --eval '(setq evil-bench-run-on-load nil)' -l scripts/evil-benchmark-runtime.el --eval '(evil-bench-window-configuration-churn 2000)'`
Expected: Baseline timing output captured for comparison.

- [ ] **Step 3: Run the benchmark after implementation**

Run the same command after byte-compiling both comparison trees with the same command, for example `emacs -Q --batch -L . -f batch-byte-compile evil-jumps.el evil-tests.el scripts/evil-benchmark-runtime.el` in each tree before benchmarking.
Expected: Measurable improvement for the window-churn workload.

### Task 4: Regression verification

**Files:**
- Modify: `evil-tests.el` (only if follow-up fixes are required)
- Modify: `scripts/evil-benchmark-runtime.el` (only if output formatting needs cleanup)

- [ ] **Step 1: Run focused jump coverage**

Run: `emacs -Q --batch -L . --eval "(setq evil-tests-run nil)" -l evil-tests.el --eval "(evil-tests-run '(or evil-test-jump evil-test-undo-jump evil-test-show-jumps-includes-scratch-buffer-jumps evil-test-show-jumps-select-action-switches-to-scratch-buffer evil-test-jump-registration-for-goto-line-actions evil-test-jumps-push-deduplicates-same-location evil-test-jumps-store-state-in-window-parameter evil-test-jumps-split-window-does-not-share-state))"`
Expected: PASS.

- [ ] **Step 2: Byte-compile changed files**

Run: `emacs -Q --batch -L . -f batch-byte-compile evil-jumps.el evil-tests.el scripts/evil-benchmark-runtime.el`
Expected: Exit code 0. Existing non-fatal warnings may remain.

- [ ] **Step 3: Run broader benchmark suite checks**

Run isolated workloads likely affected by the change, including the new window-churn workload and at least one existing workload such as `startup-local-enable`.
Expected: Window-churn improves and no material regressions appear elsewhere.

### Task 5: Commit

**Files:**
- Modify: `evil-jumps.el`
- Modify: `evil-tests.el`
- Modify: `scripts/evil-benchmark-runtime.el`
- Create: `docs/.superpowers/specs/2026-03-25-evil-jumps-window-parameter-design.md`
- Create: `docs/.superpowers/plans/2026-03-25-evil-jumps-window-parameter.md`

- [ ] **Step 1: Stage reviewed files**

Run: `git add evil-jumps.el evil-tests.el scripts/evil-benchmark-runtime.el docs/.superpowers/specs/2026-03-25-evil-jumps-window-parameter-design.md docs/.superpowers/plans/2026-03-25-evil-jumps-window-parameter.md`

- [ ] **Step 2: Create the commit**

Run: `git commit -m "Optimize jump state storage for window churn"`

- [ ] **Step 3: Verify the working tree is clean**

Run: `git status --short`
Expected: no remaining intended changes.
