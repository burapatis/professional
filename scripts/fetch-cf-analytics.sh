#!/usr/bin/env bash
# ดึงจำนวนผู้เข้าชมจาก Cloudflare Web Analytics (GraphQL API) ลง data/analytics.yaml
# GitHub Secrets ที่ต้องมี: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
# Cloudflare จำกัดช่วงเวลาต่อ query ไม่เกิน ~13 สัปดาห์ — สคริปต์แบ่งช่วงแล้วรวมผล
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/data/analytics.yaml"
STATUS_FILE="${CLOUDFLARE_ANALYTICS_STATUS_FILE:-$ROOT/data/.analytics-fetch-status}"
HUGO_CONFIG="$ROOT/hugo.toml"
CHUNK_DAYS="${CLOUDFLARE_ANALYTICS_CHUNK_DAYS:-84}"

write_status() {
  local status="$1"
  local message="$2"
  mkdir -p "$(dirname "$STATUS_FILE")"
  cat > "$STATUS_FILE" <<YAML
status: ${status}
message: "${message}"
updatedAt: "$(utc_now)"
YAML
}

warn_skip() {
  local reason="$1"
  echo "::warning title=Cloudflare Analytics::${reason}" 2>/dev/null || true
  echo "ERROR: ${reason}" >&2
  echo "Skipping visitor count fetch — site deploy continues with existing data/analytics.yaml." >&2
  write_status "skipped" "$reason"
  exit 0
}

utc_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

days_ago_utc() {
  python3 - "$1" <<'PY'
from datetime import datetime, timedelta, timezone
import sys
out = datetime.now(timezone.utc) - timedelta(days=int(sys.argv[1]))
print(out.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

add_days_utc() {
  python3 - "$1" "$2" <<'PY'
from datetime import datetime, timedelta, timezone
import sys
start = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
out = start + timedelta(days=int(sys.argv[2]))
print(out.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
}

epoch_utc() {
  python3 - "$1" <<'PY'
from datetime import datetime, timezone
import sys
print(int(datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00")).timestamp()))
PY
}

cf_api() {
  curl -fsS "https://api.cloudflare.com/client/v4/$1" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${@:2}"
}

verify_token() {
  local response status
  response=$(curl -fsS "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" || true)

  if ! echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "Cloudflare token verify response:" >&2
    echo "$response" | jq '.' >&2 || echo "$response" >&2
    warn_skip "CLOUDFLARE_API_TOKEN is invalid or expired."
  fi

  status=$(echo "$response" | jq -r '.result.status // "unknown"')
  echo "Cloudflare API token verified (status: ${status})"
}

print_graphql_errors() {
  local response="$1"
  local context="$2"

  echo "ERROR: Cloudflare GraphQL failed during ${context}." >&2
  echo "$response" | jq '.errors' >&2 || echo "$response" >&2

  if echo "$response" | jq -e '.errors[]? | select(.message | test("not authorized"; "i"))' >/dev/null 2>&1; then
    cat >&2 <<HINT
HINT: API Token ไม่มีสิทธิ์อ่าน Web Analytics ของ account นี้ หรือ CLOUDFLARE_ACCOUNT_ID ไม่ตรงกับบัญชีที่มี krujit.com
  • Cloudflare → My Profile → API Tokens → ต้องมีสิทธิ์ Account → Analytics: Read
  • ตรวจ Account ID ในหน้า Overview ของบัญชีที่ลงทะเบียน Web Analytics สำหรับ krujit.com
  • อัปเดต GitHub Secrets แล้วรัน workflow ใหม่
  • ทดสอบในเครื่อง: CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... bash scripts/test-cf-analytics.sh
HINT
  fi
}

read_beacon_token() {
  if [[ -n "${CLOUDFLARE_WEB_ANALYTICS_BEACON_TOKEN:-}" ]]; then
    echo "$CLOUDFLARE_WEB_ANALYTICS_BEACON_TOKEN"
    return
  fi
  if [[ -f "$HUGO_CONFIG" ]]; then
    grep -E 'cloudflareAnalytics(Token)?' "$HUGO_CONFIG" \
      | sed -n 's/.*= *"\([^"]*\)".*/\1/p' \
      | head -1
  fi
}

resolve_site_tag() {
  local beacon_token="$1"
  local response
  response=$(cf_api "accounts/${CLOUDFLARE_ACCOUNT_ID}/rum/site_info/list" || true)

  if ! echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "Cloudflare site list API failed:" >&2
    echo "$response" | jq '.' >&2 || echo "$response" >&2
    return 1
  fi

  local site_tag
  site_tag=$(echo "$response" | jq -r --arg token "$beacon_token" '
    (.result // [])[]
    | select(.site_token == $token or (.snippet // "" | contains($token)))
    | .site_tag
  ' | head -1)

  if [[ -z "$site_tag" ]]; then
    echo "ไม่พบ site_tag ที่ตรงกับ beacon token ใน hugo.toml" >&2
    echo "Sites visible to this token:" >&2
    echo "$response" | jq -r '(.result // [])[] | "- \(.site_tag) host=\(.host // "n/a") token=\(.site_token // "n/a")"' >&2
    return 1
  fi

  echo "$site_tag"
}

fetch_visits_range() {
  local site_tag="$1"
  local range_start="$2"
  local range_end="$3"
  local response

  read -r -d '' QUERY <<'GQL' || true
query WebAnalyticsVisits($accountTag: string!, $filter: AccountRumPageloadEventsAdaptiveGroupsFilter_InputObject!) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      rumPageloadEventsAdaptiveGroups(limit: 10000, filter: $filter) {
        count
        sum {
          visits
        }
      }
    }
  }
}
GQL

  local payload
  payload=$(jq -n \
    --arg query "$QUERY" \
    --arg accountTag "$CLOUDFLARE_ACCOUNT_ID" \
    --arg siteTag "$site_tag" \
    --arg rangeStart "$range_start" \
    --arg rangeEnd "$range_end" \
    --argjson hosts '[{"requestHost":"krujit.com"},{"requestHost":"www.krujit.com"}]' \
    '{
      query: $query,
      variables: {
        accountTag: $accountTag,
        filter: {
          AND: [
            { siteTag: $siteTag },
            { datetime_geq: $rangeStart },
            { datetime_leq: $rangeEnd },
            { bot: 0 },
            { OR: $hosts }
          ]
        }
      }
    }')

  response=$(curl -fsS "https://api.cloudflare.com/client/v4/graphql" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" || true)

  if echo "$response" | jq -e '.errors | length > 0' >/dev/null 2>&1; then
    print_graphql_errors "$response" "chunk ${range_start} → ${range_end}"
    return 1
  fi

  local groups visits pageviews
  groups=$(echo "$response" | jq '.data.viewer.accounts[0].rumPageloadEventsAdaptiveGroups // []')
  visits=$(echo "$groups" | jq '[.[].sum.visits // 0] | add // 0')
  pageviews=$(echo "$groups" | jq '[.[].count // 0] | add // 0')
  echo "${visits} ${pageviews}"
}

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  warn_skip "Cloudflare analytics secrets not set (CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID)."
fi

echo "Cloudflare account id: ${CLOUDFLARE_ACCOUNT_ID}"
verify_token

SITE_TAG="${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG:-}"
if [[ -z "$SITE_TAG" ]]; then
  BEACON_TOKEN=$(read_beacon_token)
  if [[ -z "$BEACON_TOKEN" ]]; then
    warn_skip "No cloudflareAnalytics in hugo.toml and CLOUDFLARE_WEB_ANALYTICS_SITE_TAG not set."
  fi
  echo "Resolving site_tag from beacon token in hugo.toml..."
  if ! SITE_TAG=$(resolve_site_tag "$BEACON_TOKEN"); then
    warn_skip "Could not resolve site_tag from Cloudflare API."
  fi
  echo "Using site_tag: ${SITE_TAG}"
else
  echo "Using site_tag from secret: ${SITE_TAG}"
fi

FOUNDING_YEAR="${CLOUDFLARE_ANALYTICS_SINCE_YEAR:-2025}"
LOOKBACK_DAYS="${CLOUDFLARE_ANALYTICS_LOOKBACK_DAYS:-175}"
RANGE_END="$(utc_now)"
RANGE_START="$(days_ago_utc "$LOOKBACK_DAYS")"
FOUNDING_START="${FOUNDING_YEAR}-01-01T00:00:00Z"
if [[ "$(epoch_utc "$FOUNDING_START")" -gt "$(epoch_utc "$RANGE_START")" ]]; then
  RANGE_START="$FOUNDING_START"
fi

echo "Analytics range: ${RANGE_START} → ${RANGE_END} (lookback ${LOOKBACK_DAYS}d max)"

TOTAL_VISITS=0
TOTAL_PAGEVIEWS=0
CHUNK_START="$RANGE_START"
CHUNK_NUM=0

while [[ "$(epoch_utc "$CHUNK_START")" -lt "$(epoch_utc "$RANGE_END")" ]]; do
  CHUNK_NUM=$((CHUNK_NUM + 1))
  CHUNK_END="$(add_days_utc "$CHUNK_START" "$CHUNK_DAYS")"
  if [[ "$(epoch_utc "$CHUNK_END")" -gt "$(epoch_utc "$RANGE_END")" ]]; then
    CHUNK_END="$RANGE_END"
  fi

  echo "Fetching chunk ${CHUNK_NUM}: ${CHUNK_START} → ${CHUNK_END}"
  if ! RESULT=$(fetch_visits_range "$SITE_TAG" "$CHUNK_START" "$CHUNK_END"); then
    warn_skip "GraphQL query failed on chunk ${CHUNK_NUM}."
  fi

  CHUNK_VISITS=$(echo "$RESULT" | awk '{print $1}')
  CHUNK_PAGEVIEWS=$(echo "$RESULT" | awk '{print $2}')
  TOTAL_VISITS=$((TOTAL_VISITS + CHUNK_VISITS))
  TOTAL_PAGEVIEWS=$((TOTAL_PAGEVIEWS + CHUNK_PAGEVIEWS))
  echo "  chunk visits=${CHUNK_VISITS}, pageViews=${CHUNK_PAGEVIEWS}"

  if [[ "$CHUNK_END" == "$RANGE_END" ]]; then
    break
  fi
  CHUNK_START="$CHUNK_END"
done

UPDATED_AT="$(utc_now)"

cat > "$OUT" <<YAML
# อัปเดตอัตโนมัติโดย scripts/fetch-cf-analytics.sh — ไม่ต้องแก้มือ
visits: ${TOTAL_VISITS}
pageViews: ${TOTAL_PAGEVIEWS}
updatedAt: "${UPDATED_AT}"
since: "${RANGE_START}"
periodDays: ${LOOKBACK_DAYS}
source: cloudflare-web-analytics
siteTag: "${SITE_TAG}"
YAML

write_status "ok" "visits=${TOTAL_VISITS}, pageViews=${TOTAL_PAGEVIEWS}"
echo "Visitor stats written: visits=${TOTAL_VISITS}, pageViews=${TOTAL_PAGEVIEWS} (${CHUNK_NUM} chunks)"
