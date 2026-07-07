#!/usr/bin/env bash
# ทดสอบว่า Cloudflare API token + account id ใช้งานได้กับ krujit.com
# ใช้: CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... bash scripts/test-cf-analytics.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

: "${CLOUDFLARE_API_TOKEN:?ตั้ง CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?ตั้ง CLOUDFLARE_ACCOUNT_ID}"

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

echo "=== 1) ตรวจ token ==="
curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" | jq '{success, status: .result.status}'

echo
echo "=== 2) รายการ Web Analytics sites ใน account ==="
curl -s "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/rum/site_info/list" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  | jq '{success, sites: [.result[]? | {site_tag, host, site_token}]}'

if [[ -z "${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG:-}" ]]; then
  CLOUDFLARE_WEB_ANALYTICS_SITE_TAG="$(
    grep -E 'cloudflareAnalytics(Token)?' "${SCRIPT_DIR}/../hugo.toml" \
      | sed -n 's/.*= *"\([^"]*\)".*/\1/p' \
      | head -1
  )"
  if [[ -n "$CLOUDFLARE_WEB_ANALYTICS_SITE_TAG" ]]; then
    CLOUDFLARE_WEB_ANALYTICS_SITE_TAG="$(
      curl -s "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/rum/site_info/list" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        | jq -r --arg token "$CLOUDFLARE_WEB_ANALYTICS_SITE_TAG" '
          (.result // [])[]
          | select(.site_token == $token or (.snippet // "" | contains($token)))
          | .site_tag
        ' | head -1
    )"
  fi
fi

: "${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG:?ไม่พบ site_tag — ตั้ง CLOUDFLARE_WEB_ANALYTICS_SITE_TAG หรือตรวจ hugo.toml}"

echo
echo "=== 3) ดึง visits 7 วันล่าสุด (ทดสอบเร็ว) site_tag=${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG} ==="
RANGE_START="$(days_ago_utc 7)"
RANGE_END="$(utc_now)"

read -r -d '' QUERY <<'GQL' || true
query TestVisits($accountTag: string!, $filter: AccountRumPageloadEventsAdaptiveGroupsFilter_InputObject!) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      rumPageloadEventsAdaptiveGroups(limit: 10, filter: $filter) {
        count
        sum {
          visits
        }
      }
    }
  }
}
GQL

PAYLOAD=$(jq -n \
  --arg query "$QUERY" \
  --arg accountTag "$CLOUDFLARE_ACCOUNT_ID" \
  --arg rangeStart "$RANGE_START" \
  --arg rangeEnd "$RANGE_END" \
  --arg siteTag "$CLOUDFLARE_WEB_ANALYTICS_SITE_TAG" \
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
          { OR: [{ requestHost: "krujit.com" }, { requestHost: "www.krujit.com" }] }
        ]
      }
    }
  }')

curl -s "https://api.cloudflare.com/client/v4/graphql" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD" | jq .

echo
echo "=== 4) รวม visits ทั้งหมดแบบ chunked (เหมือนตอน deploy) ==="
export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_WEB_ANALYTICS_SITE_TAG
export CLOUDFLARE_ANALYTICS_SINCE_YEAR="${CLOUDFLARE_ANALYTICS_SINCE_YEAR:-2025}"
bash "${SCRIPT_DIR}/fetch-cf-analytics.sh"
echo
cat "${SCRIPT_DIR}/../data/analytics.yaml"
