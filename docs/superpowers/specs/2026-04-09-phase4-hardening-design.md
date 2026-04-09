# Phase 4 Hardening Design

## Scope

Bring Phase 4 features to a testable and verifiable state without rewriting the already-implemented product surface.

In scope:
- backend file transfer API validation and lifecycle checks
- backend admin API regression coverage
- backend signaling helper behavior coverage for chat, clipboard, file transfer, and monitor switch
- frontend build stability for Phase 4 screens

Out of scope:
- redesigning the UI
- replacing the current signaling architecture
- broad refactors outside Phase 4 behavior

## Recommended Approach

Use backend contract-first hardening.

1. Lock the intended behavior with failing tests.
2. Make the smallest production changes needed to satisfy those tests.
3. Run frontend build verification and only patch issues that block Phase 4 usage.

This keeps TDD strict and avoids trampling the user's in-progress frontend edits.

## Risks

- Existing frontend files are currently dirty in the worktree, so edits must stay narrowly scoped.
- Some source files contain Korean text and require encoding care; new docs stay ASCII-only.
- Signaling behavior is mostly event-routing logic, so tests should assert emitted payloads directly.

## Success Criteria

- backend Phase 4 tests pass
- frontend build passes
- file transfer, admin dashboard APIs, and signaling helper events are covered by automated tests
