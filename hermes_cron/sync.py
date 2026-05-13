#!/usr/bin/env python3
"""
Deterministically sync cron jobs from config.yaml into Hermes cron state.

Behavior:
  - Job in config AND state, fields match → noop
  - Job in config AND state, fields differ → update (preserves ID + runtime state)
  - Job in config but NOT in state → create
  - Job in state but NOT in config → PRESERVED (never wiped)

The `name` field in config.yaml is the stable identity key — names must be
consistent across deployments for the idempotent matching to work.

Usage:
    python3 sync.py              # sync all jobs
    python3 sync.py --dry-run    # preview changes only
"""

import argparse
import sys
from pathlib import Path

import yaml

# ── Imports from hermes-agent (installed as a package) ──────────────
from cron.jobs import (
    create_job,
    load_jobs,
    save_jobs,
    update_job,
    list_jobs,
    _normalize_skill_list,
)

# ── Paths ───────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_PATH = SCRIPT_DIR / "config.yaml"


# ══════════════════════════════════════════════════════════════════════
# Normalization helpers (mirror create_job's normalization)
# ══════════════════════════════════════════════════════════════════════

def _norm_str(value):
    """Normalize a string field: strip, return None if empty."""
    if value is None:
        return None
    s = str(value).strip()
    return s if s else None


def _norm_list(value):
    """Normalize a list field: return sorted list or None if empty."""
    if value is None:
        return None
    if isinstance(value, str):
        items = [value.strip()] if value.strip() else []
    else:
        items = [str(v).strip() for v in value if str(v).strip()]
    return sorted(items) if items else None


def _norm_repeat(value):
    """Normalize repeat: return int or None. 0/negative → None."""
    if value is None:
        return None
    try:
        r = int(value)
        return r if r > 0 else None
    except (TypeError, ValueError):
        return None


# ══════════════════════════════════════════════════════════════════════
# Field extraction (config → normalized dict for comparison)
# ══════════════════════════════════════════════════════════════════════

def config_to_fields(job_def, existing_jobs_by_name):
    """Convert a config job entry into normalized fields for comparison.

    Returns a dict with the same keys that create_job would produce,
    normalized identically.
    """
    fields = {}

    # Required
    fields["prompt"] = _norm_str(job_def.get("prompt", ""))
    fields["schedule"] = _norm_str(job_def.get("schedule", ""))

    # Skills (normalized the same way _normalize_skill_list does it)
    raw_skill = job_def.get("skill")
    raw_skills = job_def.get("skills")
    if raw_skills is None and raw_skill is not None:
        raw_skills = [raw_skill]
    elif raw_skills is None:
        raw_skills = []
    elif isinstance(raw_skills, str):
        raw_skills = [raw_skills]
    skills = _normalize_skill_list(None, raw_skills)
    fields["skills"] = skills if skills else None

    # Model overrides
    model_config = job_def.get("model")
    if isinstance(model_config, dict):
        fields["model"] = _norm_str(model_config.get("model"))
        fields["provider"] = _norm_str(model_config.get("provider"))
        fields["base_url"] = _norm_str(model_config.get("base_url"))
    else:
        fields["model"] = _norm_str(model_config) if not isinstance(model_config, dict) else None
        fields["provider"] = _norm_str(job_def.get("provider"))
        fields["base_url"] = _norm_str(job_def.get("base_url"))

    # Optional fields
    fields["script"] = _norm_str(job_def.get("script"))
    fields["deliver"] = _norm_str(job_def.get("deliver", "origin"))
    fields["workdir"] = _norm_str(job_def.get("workdir"))
    fields["repeat"] = _norm_repeat(job_def.get("repeat"))

    # Toolsets
    fields["enabled_toolsets"] = _norm_list(job_def.get("enabled_toolsets"))

    # context_from: resolve names → IDs
    raw_ctx = job_def.get("context_from")
    if raw_ctx:
        if isinstance(raw_ctx, str):
            raw_ctx = [raw_ctx]
        resolved = []
        for ref in raw_ctx:
            ref_str = str(ref).strip()
            if ref_str in existing_jobs_by_name:
                resolved.append(existing_jobs_by_name[ref_str]["id"])
            else:
                resolved.append(ref_str)  # pass through (might be an ID already)
        fields["context_from"] = _norm_list(resolved)
    else:
        fields["context_from"] = None

    return fields


# ══════════════════════════════════════════════════════════════════════
# Field comparison (config fields vs stored job fields)
# ══════════════════════════════════════════════════════════════════════

# Fields that define a job's identity (compared for changes).
# Runtime fields (id, created_at, next_run_at, last_run_at, etc.) are excluded.
_CONFIGURABLE_FIELDS = {
    "prompt",
    "schedule",       # stored as parsed dict — need special handling
    "skills",
    "model",
    "provider",
    "base_url",
    "script",
    "context_from",
    "enabled_toolsets",
    "workdir",
    "deliver",
    "repeat",
}


def _schedule_matches(stored_schedule, config_schedule_str):
    """Compare a stored schedule dict against a config schedule string.

    We re-parse the config string through parse_schedule and compare the
    structured output (kind + key fields) rather than fuzzy-matching strings.
    """
    if not config_schedule_str:
        return stored_schedule is None
    if not stored_schedule:
        return False
    try:
        from cron.jobs import parse_schedule
        parsed = parse_schedule(config_schedule_str)
    except Exception:
        return False

    if stored_schedule.get("kind") != parsed.get("kind"):
        return False

    kind = parsed["kind"]
    if kind == "interval":
        return stored_schedule.get("minutes") == parsed.get("minutes")
    elif kind == "cron":
        return stored_schedule.get("expr") == parsed.get("expr")
    elif kind == "once":
        return stored_schedule.get("run_at") == parsed.get("run_at")
    return False


def fields_differ(config_fields, existing_job):
    """Return set of field names that differ between config and existing job.

    Only compares configurable fields; ignores runtime state.
    """
    diff = set()

    for field in _CONFIGURABLE_FIELDS:
        config_val = config_fields.get(field)
        existing_val = existing_job.get(field)

        if field == "schedule":
            if not _schedule_matches(existing_val, config_val):
                diff.add(field)
        elif field == "repeat":
            config_repeat = config_val  # already normalized: int or None
            existing_repeat = existing_val.get("times") if isinstance(existing_val, dict) else existing_val
            if config_repeat != existing_repeat:
                diff.add(field)
        elif field in ("skills", "enabled_toolsets", "context_from"):
            # Sorted list comparison
            config_list = config_val or []
            existing_list = existing_val or []
            if sorted(config_list) != sorted(existing_list):
                diff.add(field)
        else:
            if config_val != existing_val:
                diff.add(field)

    return diff


# ══════════════════════════════════════════════════════════════════════
# Sync engine
# ══════════════════════════════════════════════════════════════════════

def sync(config_path=None, dry_run=False):
    """Run the sync. Returns (actions_taken, summary_lines)."""
    if config_path is None:
        config_path = CONFIG_PATH

    if not config_path.exists():
        print(f"ERROR: config.yaml not found at {config_path}", file=sys.stderr)
        sys.exit(1)

    config = yaml.safe_load(config_path.read_text())
    config_jobs = config.get("jobs", [])
    if not config_jobs:
        print("No jobs defined in config.yaml — nothing to sync.")
        return [], []

    existing_jobs = load_jobs()
    existing_by_name = {j["name"]: j for j in existing_jobs if j.get("name")}
    config_names = set()

    actions = []
    summary = []

    for job_def in config_jobs:
        name = _norm_str(job_def.get("name"))
        if not name:
            print("WARNING: skipping config entry without a name", file=sys.stderr)
            continue

        config_names.add(name)

        # Normalize config fields (resolve context_from names to IDs)
        config_fields = config_to_fields(job_def, existing_by_name)

        if name in existing_by_name:
            existing = existing_by_name[name]
            diff = fields_differ(config_fields, existing)

            if not diff:
                summary.append(f"  ✓ {name} — no changes needed")
                continue

            if dry_run:
                summary.append(f"  ~ {name} — WOULD update ({', '.join(sorted(diff))})")
                actions.append(("would_update", name, diff))
                continue

            # Build updates dict — use raw config values, update_job re-normalizes
            updates = {}
            for field in diff:
                if field == "schedule":
                    updates["schedule"] = job_def["schedule"]
                elif field == "repeat":
                    updates["repeat"] = {"times": config_fields["repeat"], "completed": existing.get("repeat", {}).get("completed", 0)}
                else:
                    updates[field] = config_fields[field]

            result = update_job(existing["id"], updates)
            if result:
                summary.append(f"  ✎ {name} — updated ({', '.join(sorted(diff))})")
                actions.append(("updated", name, diff))
            else:
                summary.append(f"  ✗ {name} — UPDATE FAILED")
        else:
            # Not found → create
            if dry_run:
                summary.append(f"  + {name} — WOULD create")
                actions.append(("would_create", name, None))
                continue

            try:
                created = create_job(
                    prompt=config_fields["prompt"],
                    schedule=job_def["schedule"],  # raw string
                    name=name,
                    repeat=config_fields["repeat"],
                    deliver=config_fields["deliver"],
                    skills=config_fields.get("skills"),
                    model=config_fields.get("model"),
                    provider=config_fields.get("provider"),
                    base_url=config_fields.get("base_url"),
                    script=config_fields.get("script"),
                    context_from=config_fields.get("context_from"),
                    enabled_toolsets=config_fields.get("enabled_toolsets"),
                    workdir=config_fields.get("workdir"),
                )
                summary.append(f"  + {name} — created (id={created['id']})")
                actions.append(("created", name, created["id"]))
            except Exception as e:
                summary.append(f"  ✗ {name} — CREATE FAILED: {e}")

    # Report jobs in state but not in config (preserved — never deleted)
    orphans = [j for j in existing_jobs if j.get("name") not in config_names]
    if orphans:
        orphan_names = [j.get("name", j.get("id", "?")) for j in orphans]
        summary.append(f"\n  📦 {len(orphans)} job(s) in state but not in config (preserved):")
        for oname in orphan_names:
            summary.append(f"     - {oname}")

    return actions, summary


# ══════════════════════════════════════════════════════════════════════
# CLI
# ══════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Sync cron jobs from config.yaml into Hermes cron state"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without applying them",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=CONFIG_PATH,
        help=f"Path to config.yaml (default: {CONFIG_PATH})",
    )
    args = parser.parse_args()
    config_path = args.config

    print(f"📋 Syncing from {config_path}")
    if args.dry_run:
        print("🔍 DRY RUN — no changes will be applied\n")

    actions, summary = sync(config_path=config_path, dry_run=args.dry_run)

    print("\n".join(summary))

    creates = sum(1 for a in actions if a[0] in ("created", "would_create"))
    updates = sum(1 for a in actions if a[0] in ("updated", "would_update"))
    print(f"\n🏁 Done. {creates} created, {updates} updated.")


if __name__ == "__main__":
    main()
