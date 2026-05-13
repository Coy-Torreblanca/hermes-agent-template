#!/usr/bin/env python3
"""
Integration test for sync.py.

Validates the full lifecycle:
  1. Delete a config-defined job from state
  2. Run sync → job is re-created
  3. Run sync again → noop (idempotent)
  4. Delete job from state again
  5. Run sync → job is re-created again
  6. Verify all other config jobs remain untouched

Uses gbrain-doctor as the test subject (least disruptive).
"""

import subprocess
import sys
from pathlib import Path

import yaml
from cron.jobs import load_jobs, save_jobs, remove_job

SCRIPT_DIR = Path(__file__).resolve().parent
SYNC_SCRIPT = SCRIPT_DIR / "sync.py"
CONFIG_PATH = SCRIPT_DIR / "config.yaml"

TEST_JOB_NAME = "gbrain-doctor"
PASS = 0
FAIL = 0


def ok(msg):
    global PASS
    PASS += 1
    print(f"  ✅ {msg}")


def fail(msg):
    global FAIL
    FAIL += 1
    print(f"  ❌ {msg}")


def assert_eq(actual, expected, label):
    if actual == expected:
        ok(f"{label}: {actual}")
    else:
        fail(f"{label}: expected {expected!r}, got {actual!r}")


def run_sync(dry_run=False):
    """Run sync.py and return (exit_code, stdout)."""
    cmd = [sys.executable, str(SYNC_SCRIPT)]
    if dry_run:
        cmd.append("--dry-run")
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(SCRIPT_DIR))
    return result.returncode, result.stdout


def get_job_by_name(name):
    """Return job dict by name, or None."""
    for j in load_jobs():
        if j.get("name") == name:
            return j
    return None


# ══════════════════════════════════════════════════════════════════════
# Pre-flight: verify config has the test job
# ══════════════════════════════════════════════════════════════════════

print("── Pre-flight ──")
config = yaml.safe_load(CONFIG_PATH.read_text())
config_names = [j["name"] for j in config["jobs"]]
assert TEST_JOB_NAME in config_names, f"{TEST_JOB_NAME} not in config.yaml"
ok(f"{TEST_JOB_NAME} is defined in config.yaml")
print(f"  Config jobs: {config_names}")

# ══════════════════════════════════════════════════════════════════════
# Phase 1: Delete → Sync → Validate (first create)
# ══════════════════════════════════════════════════════════════════════

print("\n── Phase 1: Delete → Sync → Validate ──")

# 1a. Remove the test job from state
job_before = get_job_by_name(TEST_JOB_NAME)
if job_before:
    removed = remove_job(job_before["id"])
    assert_eq(removed, True, f"removed {TEST_JOB_NAME} (id={job_before['id']})")
else:
    ok(f"{TEST_JOB_NAME} was already absent from state")

# 1b. Verify it's gone
job_gone = get_job_by_name(TEST_JOB_NAME)
assert_eq(job_gone, None, f"{TEST_JOB_NAME} absent from state")

# 1c. Run sync — should re-create
exit_code, stdout = run_sync()
assert_eq(exit_code, 0, "sync exit code")
if f"+ {TEST_JOB_NAME} — created" in stdout:
    ok(f"sync created {TEST_JOB_NAME}")
else:
    fail(f"sync did NOT create {TEST_JOB_NAME}\nSync output:\n{stdout}")

# 1d. Verify job exists and matches config
created = get_job_by_name(TEST_JOB_NAME)
assert created is not None, f"{TEST_JOB_NAME} exists after sync"
if created:
    config_job = next(j for j in config["jobs"] if j["name"] == TEST_JOB_NAME)
    assert_eq(created["schedule_display"], config_job["schedule"], "schedule matches config")
    assert_eq(created["deliver"], "discord", "deliver matches config")
    assert_eq("second-brain" in (created.get("skills") or []), True, "skills include second-brain")

# ══════════════════════════════════════════════════════════════════════
# Phase 2: Sync again → Noop (idempotent)
# ══════════════════════════════════════════════════════════════════════

print("\n── Phase 2: Sync again → Noop (idempotent) ──")

exit_code, stdout = run_sync()
assert_eq(exit_code, 0, "sync exit code")
if f"✓ {TEST_JOB_NAME} — no changes needed" in stdout:
    ok(f"sync noop'd {TEST_JOB_NAME} (idempotent)")
else:
    fail(f"sync did NOT noop {TEST_JOB_NAME}\nSync output:\n{stdout}")

# Job should still be there, unchanged
still_there = get_job_by_name(TEST_JOB_NAME)
assert still_there is not None, f"{TEST_JOB_NAME} still exists"
if still_there and created:
    assert_eq(still_there["id"], created["id"], "job ID preserved after noop")

# ══════════════════════════════════════════════════════════════════════
# Phase 3: Delete → Sync → Validate again
# ══════════════════════════════════════════════════════════════════════

print("\n── Phase 3: Delete → Sync → Validate (re-create) ──")

# 3a. Remove again
removed = remove_job(still_there["id"])
assert_eq(removed, True, f"removed {TEST_JOB_NAME} again")

job_gone2 = get_job_by_name(TEST_JOB_NAME)
assert_eq(job_gone2, None, f"{TEST_JOB_NAME} absent again")

# 3b. Sync — should re-create
exit_code, stdout = run_sync()
assert_eq(exit_code, 0, "sync exit code")
if f"+ {TEST_JOB_NAME} — created" in stdout:
    ok(f"sync re-created {TEST_JOB_NAME}")
else:
    fail(f"sync did NOT re-create {TEST_JOB_NAME}\nSync output:\n{stdout}")

recreated = get_job_by_name(TEST_JOB_NAME)
assert recreated is not None, f"{TEST_JOB_NAME} re-created in state"

# ══════════════════════════════════════════════════════════════════════
# Phase 4: Verify other jobs untouched
# ══════════════════════════════════════════════════════════════════════

print("\n── Phase 4: Other jobs untouched ──")
all_jobs = {j["name"]: j for j in load_jobs()}
for name in config_names:
    if name == TEST_JOB_NAME:
        continue
    if name in all_jobs:
        ok(f"{name} still in state")
    else:
        fail(f"{name} MISSING from state")

# ══════════════════════════════════════════════════════════════════════
# Results
# ══════════════════════════════════════════════════════════════════════

print(f"\n{'='*50}")
print(f"  Results: {PASS} passed, {FAIL} failed")
print(f"{'='*50}")

sys.exit(0 if FAIL == 0 else 1)
