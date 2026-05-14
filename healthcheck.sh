#!/bin/bash
# Personal AI Health Check — runs on Railway deploy AND every 24h via cron
set -e

GBRAIN_HOME="${GBRAIN_HOME:-/data/.gbrain}"
BRAIN_PATH="${SYNCTHING_FOLDER_PATH:-/data/syncthing/Sync}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

overall="pass"
failures=()
warnings=()

echo "═══════════════════════════════════════════════"
echo "  Personal AI Health Check — $TIMESTAMP"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Supervisor Process Health ──────────────────────
echo "── 1. Supervisor Process Health ──────────────────"

SUPERVISOR_PROGRAMS=("hermes" "syncthing-config" "syncthing" "gbrain-init" "gbrain-minions" "gbrain-mcp")

# Try supervisorctl first
if command -v supervisorctl &> /dev/null && [ -S /var/run/supervisor.sock ] 2>/dev/null; then
    # Use supervisorctl
    for prog in "${SUPERVISOR_PROGRAMS[@]}"; do
        status=$(supervisorctl status "$prog" 2>/dev/null | awk '{print $2}')
        case "$status" in
            RUNNING)  pass "supervisor/$prog: RUNNING" ;;
            STOPPED)  warn "supervisor/$prog: STOPPED"  ; warnings+=("$prog stopped"); overall="warn" ;;
            FATAL)    fail "supervisor/$prog: FATAL"     ; failures+=("$prog fatal"); overall="fail" ;;
            *)        
                # Check via PID instead
                pid_file="/tmp/supervisor-$prog.pid"
                if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                    pass "supervisor/$prog: RUNNING (via PID)"
                else
                    warn "supervisor/$prog: UNKNOWN (no status)"  
                    warnings+=("$prog status unknown")
                    overall="warn"
                fi
                ;;
        esac
    done
else
    # Fallback: check processes via /proc (pgrep not consistently available)
    echo "  (supervisorctl unavailable — checking /proc directly)"
    declare -A PROC_MAP
    PROC_MAP["hermes"]="hermes_start.sh"
    PROC_MAP["syncthing"]="syncthing"
    PROC_MAP["gbrain"]="bun.*cli.ts serve"
    PROC_MAP["gateway"]="hermes gateway"
    
    for name in "${!PROC_MAP[@]}"; do
        if grep -ql "${PROC_MAP[$name]}" /proc/*/cmdline 2>/dev/null; then
            pass "process/$name: RUNNING"
        else
            fail "process/$name: NOT FOUND"
            failures+=("$name process missing")
            overall="fail"
        fi
    done
fi
echo ""

# ── 2. Cron Job Health ────────────────────────────────
echo "── 2. Cron Job Health ────────────────────────────"

CRON_CONFIG="/app/hermes_cron/config.yaml"
if [ -f "$CRON_CONFIG" ]; then
    pass "cron/config: config.yaml found"
    
    # Count configured jobs (count top-level dashes with a name key)
    JOB_COUNT=$(grep -c "^- name:" "$CRON_CONFIG" 2>/dev/null || echo 0)
    if [ "$JOB_COUNT" -ge 5 ]; then
        pass "cron/jobs: $JOB_COUNT jobs configured (expected 5+)"
    else
        warn "cron/jobs: only $JOB_COUNT jobs configured (expected 5+)"
        warnings+=("Only $JOB_COUNT cron jobs configured")
        overall="warn"
    fi
    
    # Check for sync.py
    if [ -f "/app/hermes_cron/sync.py" ]; then
        pass "cron/sync: sync.py found"

        # Run dry-run to detect drift between config and cron state
        SYNC_OUTPUT=$(python3 /app/hermes_cron/sync.py --dry-run 2>/dev/null)
        ORPHANS=$(echo "$SYNC_OUTPUT" | grep -c "in state but not in config" || true)
        PENDING=$(echo "$SYNC_OUTPUT" | grep -c "WOULD" || true)

        if [ "$ORPHANS" -gt 0 ]; then
            ORPHAN_JOBS=$(echo "$SYNC_OUTPUT" | grep "^- " | tr '\n' '; ' | sed 's/; $//')
            warn "cron/drift: $ORPHANS orphan job(s) in state but not in config: $ORPHAN_JOBS"
            warnings+=("$ORPHANS cron orphan(s): $ORPHAN_JOBS")
            overall="warn"
        fi

        if [ "$PENDING" -gt 0 ]; then
            PENDING_DETAILS=$(echo "$SYNC_OUTPUT" | grep "WOULD" | tr '\n' '; ' | sed 's/; $//')
            warn "cron/drift: $PENDING pending change(s) — $PENDING_DETAILS"
            warnings+=("$PENDING cron change(s) pending sync")
            overall="warn"
        fi

        if [ "$ORPHANS" -eq 0 ] && [ "$PENDING" -eq 0 ]; then
            pass "cron/sync: state matches config.yaml (no drift)"
        fi
    else
        fail "cron/sync: sync.py MISSING"
        failures+=("sync.py missing")
        overall="fail"
    fi
else
    warn "cron/config: config.yaml MISSING"
    warnings+=("cron config missing")
    overall="warn"
fi
echo ""

# ── 3. gbrain Health ──────────────────────────────────
echo "── 3. gbrain Health ──────────────────────────────"

# Check gbrain CLI (add bun path — gbrain is installed via bun globally)
export PATH="/root/.bun/bin:$PATH"
if command -v gbrain &> /dev/null; then
    pass "gbrain/cli: gbrain command found"
    
    # Doctor check (non-blocking — capture output)
    DOCTOR_OUTPUT=$(gbrain doctor --json 2>/dev/null | grep "^{" || echo '{"status":"error"}')
    
    # Extract key metrics — gbrain doctor uses flat JSON with checks array
    SCORE=$(echo "$DOCTOR_OUTPUT" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    score = d.get('health_score','N/A')
    # Find specific checks
    checks = {c['name']:c for c in d.get('checks',[])}
    embed = checks.get('embeddings',{}).get('message','N/A')
    brain = checks.get('brain_score',{}).get('message','N/A')
    print(f'{score}|{embed}|{brain}')
except:
    print('N/A|N/A|N/A')
" 2>/dev/null || echo "N/A|N/A|N/A")
    
    SCORE_VAL=$(echo "$SCORE" | cut -d'|' -f1)
    EMBED_MSG=$(echo "$SCORE" | cut -d'|' -f2)
    BRAIN_MSG=$(echo "$SCORE" | cut -d'|' -f3)
    
    if [ "$SCORE_VAL" != "N/A" ] && [ "$SCORE_VAL" -ge 50 ] 2>/dev/null; then
        pass "gbrain/health: score=$SCORE_VAL"
    elif [ "$SCORE_VAL" != "N/A" ]; then
        warn "gbrain/health: score=$SCORE_VAL (below 50)"
        warnings+=("gbrain score=$SCORE_VAL")
        overall="warn"
    else
        warn "gbrain/health: score not parseable from doctor"
        warnings+=("gbrain doctor unparseable")
        overall="warn"
    fi
    echo "  embed=$EMBED_MSG  brain=$BRAIN_MSG"
    
    # Stats
    STATS=$(gbrain stats 2>/dev/null | head -5 || echo "stats unavailable")
    echo "  stats: $(echo "$STATS" | head -1)"
else
    fail "gbrain/cli: gbrain command NOT FOUND"
    failures+=("gbrain CLI missing")
    overall="fail"
fi
echo ""

# ── 4. Database Connectivity ──────────────────────────
echo "── 4. Database Connectivity ──────────────────────"

if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:/]*\).*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT="${DB_PORT:-5432}"
    
    if timeout 5 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
        pass "database: postgres reachable at $DB_HOST:$DB_PORT"
    else
        fail "database: postgres UNREACHABLE at $DB_HOST:$DB_PORT"
        failures+=("database unreachable")
        overall="fail"
    fi
else
    warn "database: DATABASE_URL not set (maybe deferred)"
    warnings+=("DATABASE_URL not set")
    overall="warn"
fi
echo ""

# ── 5. Volume / Disk ──────────────────────────────────
echo "── 5. Volume / Disk ──────────────────────────────"

if [ -d "/data" ]; then
    DISK_USAGE=$(df -h /data | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -lt 80 ]; then
        pass "volume/disk: ${DISK_USAGE}% used"
    elif [ "$DISK_USAGE" -lt 95 ]; then
        warn "volume/disk: ${DISK_USAGE}% used (approaching limit)"
        warnings+=("disk at ${DISK_USAGE}%")
        overall="warn"
    else
        fail "volume/disk: ${DISK_USAGE}% used (CRITICAL)"
        failures+=("disk critical at ${DISK_USAGE}%")
        overall="fail"
    fi
    
    # Check syncthing data
    if [ -d "$BRAIN_PATH" ]; then
        FILE_COUNT=$(find "$BRAIN_PATH" -name '*.md' -type f 2>/dev/null | wc -l)
        pass "volume/brain: $FILE_COUNT markdown files in sync folder"
    else
        warn "volume/brain: sync folder NOT FOUND at $BRAIN_PATH"
        warnings+=("sync folder missing")
        overall="warn"
    fi
else
    fail "volume: /data mount NOT FOUND"
    failures+=("/data volume missing")
    overall="fail"
fi
echo ""

# ── 6. Network / Endpoint Health ──────────────────────
echo "── 6. Gateway / API Health ───────────────────────"

# Check Hermes gateway
if command -v hermes &> /dev/null; then
    HERMES_VERSION=$(hermes --version 2>/dev/null | head -1)
    pass "hermes/cli: $HERMES_VERSION"
else
    fail "hermes/cli: hermes command NOT FOUND"
    failures+=("hermes CLI missing")
    overall="fail"
fi

# Check if MCP server is responsive (gbrain serve)
if curl -sf http://127.0.0.1:8000/health > /dev/null 2>&1; then
    pass "health/endpoint: self-test OK"
else
    warn "health/endpoint: self-test failed (may be expected on cold start)"
    warnings+=("health endpoint self-test failed")
    overall="warn"
fi
echo ""

# ── Summary ───────────────────────────────────────────
echo "═══════════════════════════════════════════════"
case "$overall" in
    pass)
        echo -e "  Result: ${GREEN}PASS${NC}"
        echo "  All systems operational."
        ;;
    warn)
        echo -e "  Result: ${YELLOW}WARN${NC}"
        echo "  Warnings (${#warnings[@]}):"
        for w in "${warnings[@]}"; do echo "    ⚠ $w"; done
        ;;
    fail)
        echo -e "  Result: ${RED}FAIL${NC}"
        echo "  Failures (${#failures[@]}):"
        for f in "${failures[@]}"; do echo "    ✗ $f"; done
        ;;
esac
echo "═══════════════════════════════════════════════"

# Exit code for Railway healthcheck
case "$overall" in
    pass) exit 0 ;;
    warn) exit 0 ;;  # warn still passes deploy
    fail) exit 1 ;;
esac
