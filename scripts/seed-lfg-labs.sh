#!/usr/bin/env bash
set -euo pipefail

# Seed Paperclip with LFG Labs company, Axel (CEO), Rex (CMO), and Sam (Upwork Scout).
# Runs on the Droplet after Paperclip is up.
# Idempotent: checks if company/agents exist before creating.

API="${PAPERCLIP_API_URL:-http://127.0.0.1:3100/api}"

# ── Preflight ──────────────────────────────────────────────────────────────────

echo "=== Paperclip LFG Labs Seed ==="

# Check Paperclip is running
if ! curl -sf "$API/health" > /dev/null 2>&1; then
  echo "ERROR: Paperclip not responding at $API/health"
  echo "Start it first: systemctl --user start paperclip"
  exit 1
fi
echo "[OK] Paperclip is healthy"

# Load gateway auth token from OpenClaw secrets (extract only what we need)
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

# ── Check if already seeded ────────────────────────────────────────────────────

EXISTING_COMPANIES=$(curl -sf "$API/companies" || echo "[]")
LFG_COMPANY=$(echo "$EXISTING_COMPANIES" | python3 -c "
import sys, json
companies = json.load(sys.stdin)
# Handle both array and object-with-data responses
if isinstance(companies, dict):
    companies = companies.get('data', companies.get('companies', []))
for c in companies:
    if c.get('name') == 'LFG Labs':
        print(c['id'])
        break
" 2>/dev/null || true)

if [[ -n "$LFG_COMPANY" ]]; then
  echo "[SKIP] LFG Labs company already exists (id: $LFG_COMPANY)"
  echo "       Delete it from the Paperclip UI if you want to re-seed."
  exit 0
fi

# ── Step 1: Create LFG Labs Company ───────────────────────────────────────────

echo ""
echo "--- Step 1: Creating LFG Labs company ---"

# Company description composed from:
#   orgs/lfg-labs/COMPANY.md
#   owner/PROFILE.md
#   owner/EXPERTISE.md
COMPANY_PAYLOAD=$(python3 << 'PYEOF'
import json
desc = """LFG Labs is an AI consulting firm that designs, builds, and deploys production-ready AI agents for businesses. Founded by Sami Khawaja (6+ years software engineering, Web3/DeFi/AI agents, based in Karachi, Pakistan).

Core services: Custom AI Agent Development, OpenClaw expert deployments, end-to-end workflow automation, integration services (Slack, Discord, CRM), and ongoing support and optimization.

Current infrastructure: 9 production AI agents running 24/7 on a DigitalOcean Droplet via a single OpenClaw gateway. Agents handle strategic oversight, sales coordination, Upwork job scouting, LinkedIn content, lead research, cold email outreach, LinkedIn DM automation, Reddit engagement, and X/Twitter content. All orchestrated through Discord with hub-and-spoke architecture.

Team: Sami (founder, client acquisition, operations), Anas (lead engineer, Web3 full stack), Mubashir (engineer, Web3 full stack).

Tech stack: TypeScript/Node.js (expert), Python (advanced), Rust (intermediate). OpenClaw agent framework, Claude API, Next.js, React, Playwright, Discord.js. PostgreSQL, SQLite, Redis, MongoDB. GCP, AWS, DigitalOcean, Docker, Linux/systemd.

Differentiators: Production-ready focus (not demos), deep OpenClaw expertise, 60-day deployment guarantee, end-to-end service, transparent fixed-price packages."""
print(json.dumps({"name": "LFG Labs", "description": desc}))
PYEOF
)

COMPANY_RESPONSE=$(curl -sf -X POST "$API/companies" \
  -H "Content-Type: application/json" \
  -d "$COMPANY_PAYLOAD")

COMPANY_ID=$(echo "$COMPANY_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "[OK] Company created: $COMPANY_ID"

# ── Step 2: Create Axel (CEO, openclaw_gateway) ──────────────────────────────

echo ""
echo "--- Step 2: Creating Axel (CEO) ---"

CEO_PAYLOAD=$(GATEWAY_TOKEN="$GATEWAY_AUTH_TOKEN" python3 << 'PYEOF'
import json, os
print(json.dumps({
    "name": "Axel",
    "role": "ceo",
    "title": "Chief Executive Officer",
    "capabilities": "cross-department intelligence, KPI tracking, daily briefings, bottleneck detection, revenue forecasting, capacity planning, agent fleet oversight",
    "adapterType": "openclaw_gateway",
    "adapterConfig": {
        "url": "ws://127.0.0.1:18789",
        "headers": {"x-openclaw-token": os.environ["GATEWAY_TOKEN"]},
        "sessionKeyStrategy": "fixed",
        "sessionKey": "paperclip-axel",
        "disableDeviceAuth": True
    }
}))
PYEOF
)
CEO_RESPONSE=$(curl -sf -X POST "$API/companies/$COMPANY_ID/agents" \
  -H "Content-Type: application/json" \
  -d "$CEO_PAYLOAD")

CEO_ID=$(echo "$CEO_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "[OK] Axel (CEO) created: $CEO_ID"

# ── Step 3: Create Rex (CMO, reports to CEO) ──────────────────────────────────

echo ""
echo "--- Step 3: Creating Rex (CMO) ---"

REX_PAYLOAD=$(GATEWAY_TOKEN="$GATEWAY_AUTH_TOKEN" REPORTS_TO="$CEO_ID" python3 << 'PYEOF'
import json, os
print(json.dumps({
    "name": "Rex",
    "role": "cmo",
    "title": "Head of Sales & Marketing",
    "reportsTo": os.environ["REPORTS_TO"],
    "capabilities": "sales coordination, marketing oversight, pipeline review, agent delegation, content strategy",
    "adapterType": "openclaw_gateway",
    "adapterConfig": {
        "url": "ws://127.0.0.1:18789",
        "headers": {"x-openclaw-token": os.environ["GATEWAY_TOKEN"]},
        "sessionKeyStrategy": "fixed",
        "sessionKey": "paperclip-rex",
        "disableDeviceAuth": True
    }
}))
PYEOF
)
REX_RESPONSE=$(curl -sf -X POST "$API/companies/$COMPANY_ID/agents" \
  -H "Content-Type: application/json" \
  -d "$REX_PAYLOAD")

REX_ID=$(echo "$REX_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "[OK] Rex (CMO) created: $REX_ID (reports to CEO: $CEO_ID)"

# ── Step 4: Create Sam (reports to Rex) ────────────────────────────────────────

echo ""
echo "--- Step 4: Creating Sam (Upwork Job Scout) ---"

SAM_PAYLOAD=$(GATEWAY_TOKEN="$GATEWAY_AUTH_TOKEN" REPORTS_TO="$REX_ID" python3 << 'PYEOF'
import json, os
print(json.dumps({
    "name": "Sam",
    "role": "general",
    "title": "Upwork Job Scout",
    "reportsTo": os.environ["REPORTS_TO"],
    "capabilities": "upwork job search, job scoring, opportunity filtering, proposal drafting",
    "adapterType": "openclaw_gateway",
    "adapterConfig": {
        "url": "ws://127.0.0.1:18789",
        "headers": {"x-openclaw-token": os.environ["GATEWAY_TOKEN"]},
        "sessionKeyStrategy": "issue",
        "disableDeviceAuth": True
    }
}))
PYEOF
)
SAM_RESPONSE=$(curl -sf -X POST "$API/companies/$COMPANY_ID/agents" \
  -H "Content-Type: application/json" \
  -d "$SAM_PAYLOAD")

SAM_ID=$(echo "$SAM_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "[OK] Sam created: $SAM_ID (reports to Rex: $REX_ID)"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "=== Seed Complete ==="
echo ""
echo "Company:  LFG Labs ($COMPANY_ID)"
echo "CEO:      Axel ($CEO_ID) [openclaw_gateway]"
echo "CMO:      Rex ($REX_ID) -> reports to Axel [openclaw_gateway]"
echo "Scout:    Sam ($SAM_ID) -> reports to Rex [openclaw_gateway]"
echo ""
echo "Hierarchy:"
echo "  Axel (ceo)"
echo "    └── Rex (cmo)"
echo "          └── Sam (general)"
echo ""
echo "Next steps:"
echo "  1. Open http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo '159.65.146.65'):3100"
echo "  2. Verify org chart in dashboard"
echo "  3. Test wakeup: curl -X POST $API/agents/$SAM_ID/wakeup -H 'Content-Type: application/json' -d '{\"source\":\"on_demand\",\"reason\":\"integration test\"}'"
