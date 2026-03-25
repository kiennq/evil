# Evil Jumps Window-Parameter Design

## Goal

Reduce `evil-jumps` window-management overhead by replacing the global per-window hash table with window-local parameter storage while preserving current jump semantics.

## Current Problem

`evil-jumps` currently stores per-window jump state in the global variable `evil--jumps-window-jumps`. This requires:

- hash lookup on each state access
- manual cleanup of dead windows during `window-configuration-change-hook`
- a full `maphash` sweep on every window-configuration change

The cleanup sweep is unnecessary because the jump state belongs to a specific live window. Emacs window parameters already provide lifecycle-coupled storage.

## Proposed Design

Store each window's `evil-jumps-struct` in a dedicated window parameter named `evil-jumps`.

### Core access path

- `evil--jumps-get-current` becomes the only constructor/accessor for per-window jump state
- it reads `(window-parameter window 'evil-jumps)`
- when missing, it creates a fresh `evil-jumps-struct` and stores it with `set-window-parameter`

### Window copy behavior

`evil--jumps-window-configuration-hook` keeps its current semantic role: when a new target window appears and has no jump data yet, copy the source window's ring, current index, and previous position into the target window.

The hook no longer needs dead-window cleanup because stale state disappears with the window itself.

### Split-window inheritance risk

Emacs copies window parameters when splitting windows. That means a newly split window may initially inherit the exact same `evil-jumps-struct` object as its source window. If left unchanged, both windows would mutate the same jump ring.

To preserve current semantics, the implementation must detect this shared-state case and replace it with a deep copy for the new window. The minimum safe copy is:

- a distinct `evil-jumps-struct`
- a copied ring via `ring-copy`
- copied `idx`
- copied `previous-pos`

The implementation may achieve this either by clearing the new window parameter before copying or by detecting shared object identity and replacing it with a fresh copy.

### Compatibility boundaries

Behavior must remain unchanged for:

- jump backward / forward in one window
- cross-buffer jumps
- buffer-target jumps such as `*scratch*`
- jump-list branching when a new jump is created after jumping backward
- split-window inheritance of jump state

## Testing Strategy

Add focused regression tests before implementation:

1. `evil--jumps-get-current` stores state in the selected window parameter
2. split-window/window-configuration handling copies jump state into a new window using the parameter-backed accessor
3. split-window children do not share the same ring object as their source window
4. existing jump behavior tests continue to pass unchanged

## Benchmark Strategy

Add a dedicated benchmark workload for window churn, exercising repeated split/delete window flows while Evil jump tracking is active.

Compare before/after using the same byte-compilation method in both trees. Keep the change only if the new workload shows measurable improvement and the existing benchmark suite does not show regressions.

The benchmark should force repeated window-configuration changes that exercise split, selection change, and collapse back to one window so the old `maphash` cleanup path and the new parameter-backed path are compared fairly.

## Files Expected To Change

- `evil-jumps.el`
- `evil-tests.el`
- `scripts/evil-benchmark-runtime.el`

## Non-Goals

- changing jump entry representation
- changing savehist persistence format
- broad refactors outside `evil-jumps`

## Cleanup Requirement

Remove the obsolete `evil--jumps-window-jumps` global storage and verify no production references remain after the migration.
