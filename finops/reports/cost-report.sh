#!/usr/bin/env bash
# =============================================================
# Weekly FinOps cost report for the Orbital platform.
# Queries Kubecost API and posts a summary to Slack.
#
# Schedule via GitHub Actions (see .github/workflows/finops-report.yml)
# or as a CronJob in Kubernetes.
#
# Usage:
#   KUBECOST_URL=http://localhost:9090 SLACK_WEBHOOK=https://... bash finops/reports/cost-report.sh
# =============================================================
set -euo pipefail

KUBECOST_URL="${KUBECOST_URL:-http://localhost:9090}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:?Set SLACK_WEBHOOK env var}"
WINDOW="lastweek"

echo "Fetching cost data from Kubecost..."

# Total cluster cost last week
TOTAL=$(curl -s "${KUBECOST_URL}/model/allocation" \
  --get \
  --data-urlencode "window=${WINDOW}" \
  --data-urlencode "aggregate=cluster" \
  --data-urlencode "accumulate=true" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
sets = data.get('data', [])
if sets:
    total = sum(v.get('totalCost', 0) for v in sets[0].values())
    print(f'\${total:.2f}')
else:
    print('N/A')
")

# Orbital namespace cost
ORBITAL=$(curl -s "${KUBECOST_URL}/model/allocation" \
  --get \
  --data-urlencode "window=${WINDOW}" \
  --data-urlencode "aggregate=namespace" \
  --data-urlencode "accumulate=true" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
sets = data.get('data', [])
cost = 0
if sets:
    for ns, v in sets[0].items():
        if 'orbital' in ns.lower():
            cost += v.get('totalCost', 0)
print(f'\${cost:.2f}')
")

# Idle/waste cost
IDLE=$(curl -s "${KUBECOST_URL}/model/allocation" \
  --get \
  --data-urlencode "window=${WINDOW}" \
  --data-urlencode "aggregate=cluster" \
  --data-urlencode "includeIdle=true" \
  --data-urlencode "accumulate=true" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
sets = data.get('data', [])
idle = 0
if sets:
    for k, v in sets[0].items():
        if '__idle__' in k:
            idle += v.get('totalCost', 0)
print(f'\${idle:.2f}')
")

# Efficiency score
EFFICIENCY=$(curl -s "${KUBECOST_URL}/model/clusterInfo" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
eff = data.get('clusterEfficiency', 0) * 100
print(f'{eff:.1f}%')
" 2>/dev/null || echo "N/A")

echo "Total: ${TOTAL} | Orbital: ${ORBITAL} | Idle: ${IDLE} | Efficiency: ${EFFICIENCY}"

# Post to Slack
WEEK=$(date -u -d "last Monday" +"%b %d" 2>/dev/null || date -u -v-Mon +"%b %d")

curl -s -X POST "$SLACK_WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "{
    \"text\": \"Weekly Orbital FinOps Report\",
    \"blocks\": [
      {
        \"type\": \"header\",
        \"text\": {\"type\": \"plain_text\", \"text\": \"Orbital — Weekly Cost Report (${WEEK})\"}
      },
      {
        \"type\": \"section\",
        \"fields\": [
          {\"type\": \"mrkdwn\", \"text\": \"*Total cluster cost*\n${TOTAL}\"},
          {\"type\": \"mrkdwn\", \"text\": \"*Orbital namespace*\n${ORBITAL}\"},
          {\"type\": \"mrkdwn\", \"text\": \"*Idle/waste cost*\n${IDLE}\"},
          {\"type\": \"mrkdwn\", \"text\": \"*Cluster efficiency*\n${EFFICIENCY}\"}
        ]
      },
      {
        \"type\": \"section\",
        \"text\": {\"type\": \"mrkdwn\", \"text\": \"<http://kubecost.your-domain.com|View full report in Kubecost>\"}
      }
    ]
  }"

echo "Report posted to Slack."
