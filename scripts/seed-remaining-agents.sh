#!/usr/bin/env bash
set -euo pipefail

# Add remaining 6 agents to Paperclip (Maya, Ivy, Zane, Leo, Sage, Jax).
# Requires LFG Labs company + Rex (CMO) to already exist.
# Idempotent: checks if agents exist before creating.

API="${PAPERCLIP_API_URL:-http://127.0.0.1:3100/api}"

echo "=== Paperclip: Seed Remaining Agents ==="

# ── Preflight ──────────────────────────────────────────────────────────────────

if ! curl -sf "$API/health" > /dev/null 2>&1; then
  echo "ERROR: Paperclip not responding at $API/health"
  exit 1
fi
echo "[OK] Paperclip is healthy"

# Load gateway auth token
if [[ -z "${GATEWAY_AUTH_TOKEN:-}" ]]; then
  if [[ -f ~/.openclaw/.env ]]; then
    GATEWAY_AUTH_TOKEN=$(grep '^GATEWAY_AUTH_TOKEN=' ~/.openclaw/.env | cut -d'=' -f2- | tr -d '"' || true)
  fi
fi

if [[ -z "${GATEWAY_AUTH_TOKEN:-}" ]]; then
  echo "ERROR: GATEWAY_AUTH_TOKEN not set and not found in ~/.openclaw/.env"
  exit 1
fi
echo "[OK] Gateway auth token loaded"

# ── Find LFG Labs company ────────────────────────────────────────────────────

EXISTING_COMPANIES=$(curl -sf "$API/companies" || echo "[]")
COMPANY_ID=$(echo "$EXISTING_COMPANIES" | python3 -c "
import sys, json
companies = json.load(sys.stdin)
if isinstance(companies, dict):
    companies = companies.get('data', companies.get('companies', []))
for c in companies:
    if c.get('name') == 'LFG Labs':
        print(c['id'])
        break
" 2>/dev/null || true)

if [[ -z "$COMPANY_ID" ]]; then
  echo "ERROR: LFG Labs company not found. Run seed-lfg-labs.sh first."
  exit 1
fi
echo "[OK] LFG Labs company: $COMPANY_ID"

# ── Find Rex (CMO) ───────────────────────────────────────────────────────────

EXISTING_AGENTS=$(curl -sf "$API/companies/$COMPANY_ID/agents" || echo "[]")
REX_ID=$(echo "$EXISTING_AGENTS" | python3 -c "
import sys, json
agents = json.load(sys.stdin)
if isinstance(agents, dict):
    agents = agents.get('data', agents.get('agents', []))
for a in agents:
    if a.get('name') == 'Rex':
        print(a['id'])
        break
" 2>/dev/null || true)

if [[ -z "$REX_ID" ]]; then
  echo "ERROR: Rex (CMO) not found. Run seed-lfg-labs.sh first."
  exit 1
fi
echo "[OK] Rex (CMO): $REX_ID"

# ── Check which agents already exist ─────────────────────────────────────────

existing_agent_names=$(echo "$EXISTING_AGENTS" | python3 -c "
import sys, json
agents = json.load(sys.stdin)
if isinstance(agents, dict):
    agents = agents.get('data', agents.get('agents', []))
for a in agents:
    print(a.get('name', ''))
" 2>/dev/null || true)

# Helper: create agent if not exists
create_agent() {
  local name="$1"
  local role="$2"
  local title="$3"
  local capabilities="$4"
  local session_key="$5"

  if echo "$existing_agent_names" | grep -qx "$name"; then
    echo "[SKIP] $name already exists"
    return
  fi

  local payload
  payload=$(GATEWAY_TOKEN="$GATEWAY_AUTH_TOKEN" REPORTS_TO="$REX_ID" \
    AGENT_NAME="$name" AGENT_ROLE="$role" AGENT_TITLE="$title" \
    AGENT_CAPS="$capabilities" SESSION_KEY="$session_key" \
    python3 << 'PYEOF'
import json, os
print(json.dumps({
    "name": os.environ["AGENT_NAME"],
    "role": os.environ["AGENT_ROLE"],
    "title": os.environ["AGENT_TITLE"],
    "reportsTo": os.environ["REPORTS_TO"],
    "capabilities": os.environ["AGENT_CAPS"],
    "adapterType": "openclaw_gateway",
    "adapterConfig": {
        "url": "ws://127.0.0.1:18789",
        "headers": {"x-openclaw-token": os.environ["GATEWAY_TOKEN"]},
        "sessionKeyStrategy": "issue",
        "sessionKey": os.environ["SESSION_KEY"],
        "disableDeviceAuth": True,
        "timeout": 300000
    }
}))
PYEOF
  )

  local response
  response=$(curl -sf -X POST "$API/companies/$COMPANY_ID/agents" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local agent_id
  agent_id=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
  echo "[OK] $name ($title) created: $agent_id (reports to Rex: $REX_ID)"
}

# ── Create agents ─────────────────────────────────────────────────────────────

echo ""
echo "--- Creating remaining agents (all report to Rex) ---"
echo ""

create_agent "Maya" "general" "LinkedIn Content Specialist" \
  "LinkedIn company page content, brand voice management, product-aware content generation, anti-AI-slop drafting" \
  "paperclip-maya"

create_agent "Ivy" "general" "Lead Research Specialist" \
  "lead generation, prospect research, systematic prospect profiling, lead report generation, data-driven research" \
  "paperclip-ivy"

create_agent "Zane" "general" "Cold Email Specialist" \
  "cold email outreach campaigns, persuasive email composition, data-driven targeting, follow-up sequencing" \
  "paperclip-zane"

create_agent "Leo" "general" "LinkedIn Outreach Specialist" \
  "LinkedIn DM outreach automation, relationship-focused messaging, professional conversational strategy, direct message campaigns" \
  "paperclip-leo"

create_agent "Sage" "general" "Reddit Community Engagement" \
  "Reddit community participation, value-first content contribution, native subreddit tone matching, practitioner voice" \
  "paperclip-sage"

create_agent "Jax" "general" "X/Twitter Content Specialist" \
  "X/Twitter brand content creation, sharp technical tweets, engagement-driven posting, brand voice management" \
  "paperclip-jax"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "=== Seed Complete ==="
echo ""
echo "Full hierarchy:"
echo "  Axel (CEO)"
echo "    └── Rex (CMO)"
echo "          ├── Sam (Upwork Scout)"
echo "          ├── Maya (LinkedIn Content)"
echo "          ├── Ivy (Lead Research)"
echo "          ├── Zane (Cold Email)"
echo "          ├── Leo (LinkedIn DMs)"
echo "          ├── Sage (Reddit)"
echo "          └── Jax (X/Twitter)"
echo ""
echo "Verify: curl -s $API/companies/$COMPANY_ID/agents | python3 -m json.tool"
