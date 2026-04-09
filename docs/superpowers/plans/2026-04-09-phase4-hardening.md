# Phase 4 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish Phase 4 by hardening the already-implemented backend and frontend behavior with TDD and verification.

**Architecture:** Add regression tests around backend API and signaling boundaries first, then patch production code minimally until those tests pass. Keep frontend changes limited to build-stability fixes so existing user edits are preserved.

**Tech Stack:** FastAPI, SQLAlchemy async, pytest, httpx, Socket.IO, React, TypeScript, Vite

---

### Task 1: File Transfer API Regression Tests

**Files:**
- Create: `backend/tests/file_transfer/test_file_transfer_router.py`
- Modify: `backend/app/file_transfer/router.py`

- [ ] **Step 1: Write the failing test**
  Add API tests for init, chunk upload, complete, list, and download permission/error cases.

- [ ] **Step 2: Run test to verify it fails**
  Run: `pytest backend/tests/file_transfer/test_file_transfer_router.py -q`
  Expected: FAIL because coverage or behavior is missing.

- [ ] **Step 3: Write minimal implementation**
  Patch only file-transfer validation or response behavior needed by the failing assertions.

- [ ] **Step 4: Run test to verify it passes**
  Run: `pytest backend/tests/file_transfer/test_file_transfer_router.py -q`
  Expected: PASS.

### Task 2: Admin API Regression Tests

**Files:**
- Create: `backend/tests/admin/test_admin_router.py`
- Modify: `backend/app/admin/router.py`

- [ ] **Step 1: Write the failing test**
  Add tests for admin-only access, session filtering, forced session termination, paged audit logs, user listing, and role updates.

- [ ] **Step 2: Run test to verify it fails**
  Run: `pytest backend/tests/admin/test_admin_router.py -q`
  Expected: FAIL because behavior is not fully enforced.

- [ ] **Step 3: Write minimal implementation**
  Patch admin router validation and return payloads only where tests require it.

- [ ] **Step 4: Run test to verify it passes**
  Run: `pytest backend/tests/admin/test_admin_router.py -q`
  Expected: PASS.

### Task 3: Signaling Event Routing Tests

**Files:**
- Create: `backend/tests/sessions/test_signaling.py`
- Modify: `backend/app/sessions/signaling.py`

- [ ] **Step 1: Write the failing test**
  Add direct async tests for `chat_message`, `clipboard_sync`, `file_transfer_notify`, and `switch_monitor`.

- [ ] **Step 2: Run test to verify it fails**
  Run: `pytest backend/tests/sessions/test_signaling.py -q`
  Expected: FAIL until emit targets or payload handling are verified.

- [ ] **Step 3: Write minimal implementation**
  Adjust routing logic only if the failing tests expose incorrect target or room behavior.

- [ ] **Step 4: Run test to verify it passes**
  Run: `pytest backend/tests/sessions/test_signaling.py -q`
  Expected: PASS.

### Task 4: Full Verification

**Files:**
- Modify: `frontend/src/features/session/SessionDashboard.tsx`
- Modify: `frontend/package.json`
- Modify: `frontend/tsconfig.json`
- Modify: `frontend/vite.config.ts`

- [ ] **Step 1: Run backend Phase 4 test subset**
  Run: `pytest backend/tests/admin backend/tests/file_transfer backend/tests/sessions -q`
  Expected: PASS.

- [ ] **Step 2: Run frontend build**
  Run: `npm run build`
  Expected: PASS.

- [ ] **Step 3: Write minimal implementation**
  Patch only build-blocking frontend issues that surface from the verification run.

- [ ] **Step 4: Re-run verification**
  Run: `pytest backend/tests/admin backend/tests/file_transfer backend/tests/sessions -q`
  Expected: PASS.
  Run: `npm run build`
  Expected: PASS.
