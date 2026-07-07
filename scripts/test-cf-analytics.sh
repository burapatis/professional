#!/usr/bin/env bash
# ทดสอบว่า Cloudflare API token + account id ใช้งานได้กับ krujit.com
# ใช้: CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... bash scripts/test-cf-analytics.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BEACON_TOKEN="$(
  grep -E 'cloudflareAnalytics(Token)?' "${SCRIPT_DIR}/../hugo.toml" \
    | sed -n 's/.*= *"\([^"]*\)".*/\1/p' \
    | head -1
)"

: "${CLOUDFLARE_API_TOKEN:?ตั้ง CLOUDFLARE_API_TOKEN}"

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

cf_get() {
  curl -fsS "https://api.cloudflare.com/client/v4/$1" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json"
}

echo "=== 1) ตรวจ token ==="
TOKEN_VERIFY="$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}")"
echo "$TOKEN_VERIFY" | jq '{success, status: .result.status}'

if ! echo "$TOKEN_VERIFY" | jq -e '.success == true' >/dev/null; then
  echo "ERROR: token ใช้งานไม่ได้" >&2
  exit 1
fi

echo
echo "=== 2) บัญชีที่ token นี้เข้าถึงได้ ==="
ACCOUNTS_JSON="$(cf_get "accounts?per_page=50" || true)"
echo "$ACCOUNTS_JSON" | jq '{success, accounts: [.result[]? | {id, name}]}'

if ! echo "$ACCOUNTS_JSON" | jq -e '.success == true' >/dev/null; then
  echo "ERROR: ดึงรายการ account ไม่ได้" >&2
  echo "$ACCOUNTS_JSON" | jq '.' >&2 || echo "$ACCOUNTS_JSON" >&2
  exit 1
fi

account_count="$(echo "$ACCOUNTS_JSON" | jq '.result | length')"
if [[ "$account_count" -eq 0 ]]; then
  cat >&2 <<'MSG'
ERROR: token นี้ active แต่ไม่มีสิทธิ์เข้าถึง Cloudflare account ใดเลย (accounts: [])

สาเหตุที่พบบ่อย: สร้าง token แบบ Zone-only หรือไม่ได้เลือก Account Resources

วิธีแก้ — สร้าง Custom Token ใหม่:
  1. Cloudflare → My Profile → API Tokens → Create Token → Custom token
  2. Permissions:
       • Account → Account Analytics → Read
       • Account → Account Settings → Read  (ช่วยให้ list accounts ได้)
  3. Account Resources: Include → All accounts (หรือเลือก account ที่มี krujit.com)
  4. คัดลอก Account ID จาก Dashboard → Overview (แถบขวา) ใส่ CLOUDFLARE_ACCOUNT_ID

หมายเหตุ: ถ้า thamdee.com deploy สำเร็จ ให้คัดลอก CLOUDFLARE_API_TOKEN และ
CLOUDFLARE_ACCOUNT_ID จาก GitHub Secrets ของ repo thamdee มาใส่ repo krujit โดยตรง
MSG
  exit 1
fi

echo
echo "=== 3) ค้นหา Web Analytics sites ในแต่ละ account ==="
MATCH_ACCOUNT=""
MATCH_SITE_TAG=""

while IFS= read -r account_id; do
  [[ -z "$account_id" ]] && continue
  account_name="$(echo "$ACCOUNTS_JSON" | jq -r --arg id "$account_id" '.result[] | select(.id == $id) | .name')"
  sites_json="$(curl -s "https://api.cloudflare.com/client/v4/accounts/${account_id}/rum/site_info/list" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}")"

  if ! echo "$sites_json" | jq -e '.success == true' >/dev/null; then
    echo "- account ${account_id} (${account_name}): API error"
    echo "$sites_json" | jq '{success, errors}' 2>/dev/null || echo "$sites_json"
    continue
  fi

  site_count="$(echo "$sites_json" | jq '.result | length')"
  echo "- account ${account_id} (${account_name}): ${site_count} site(s)"
  echo "$sites_json" | jq -r '.result[]? | "    host=\(.rules[0].host // "n/a") site_tag=\(.site_tag) token=\(.site_token)"'

  if [[ -n "$BEACON_TOKEN" ]]; then
    found_tag="$(echo "$sites_json" | jq -r --arg token "$BEACON_TOKEN" '
      (.result // [])[]
      | select(.site_token == $token or (.snippet // "" | contains($token)))
      | .site_tag
    ' | head -1)"
    if [[ -n "$found_tag" ]]; then
      MATCH_ACCOUNT="$account_id"
      MATCH_SITE_TAG="$found_tag"
      echo "    >>> พบ krujit.com beacon ใน account นี้ (site_tag=${found_tag})"
    fi
  fi
done < <(echo "$ACCOUNTS_JSON" | jq -r '.result[]?.id')

if [[ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo
  echo "=== 4) ทดสอบ CLOUDFLARE_ACCOUNT_ID ที่ตั้งไว้: ${CLOUDFLARE_ACCOUNT_ID} ==="
  configured_json="$(curl -s "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/rum/site_info/list" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}")"
  echo "$configured_json" | jq '{success, errors, sites: [.result[]? | {host: (.rules[0].host // "n/a"), site_tag, site_token}]}'

  if [[ "$CLOUDFLARE_ACCOUNT_ID" != "$MATCH_ACCOUNT" && -n "$MATCH_ACCOUNT" ]]; then
    echo
    echo "HINT: CLOUDFLARE_ACCOUNT_ID ปัจจุบันไม่ตรงกับ account ที่มี krujit.com"
    echo "      ใช้ค่านี้แทน: CLOUDFLARE_ACCOUNT_ID=${MATCH_ACCOUNT}"
    echo "      และตั้ง secret: CLOUDFLARE_KRUJIT_WEB_ANALYTICS_SITE_TAG=${MATCH_SITE_TAG}"
  fi
else
  echo
  echo "=== 4) ไม่ได้ตั้ง CLOUDFLARE_ACCOUNT_ID ==="
  if [[ -n "$MATCH_ACCOUNT" ]]; then
    echo "HINT: ใช้ CLOUDFLARE_ACCOUNT_ID=${MATCH_ACCOUNT}"
    echo "      และ CLOUDFLARE_KRUJIT_WEB_ANALYTICS_SITE_TAG=${MATCH_SITE_TAG}"
    CLOUDFLARE_ACCOUNT_ID="$MATCH_ACCOUNT"
  else
    echo "ERROR: ไม่พบ account ที่มี beacon token ของ krujit.com" >&2
    echo "ตรวจใน Cloudflare Dashboard → Web Analytics ว่าเพิ่ม krujit.com ในบัญชีไหน" >&2
    exit 1
  fi
fi

if [[ -z "${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG:-}" ]]; then
  if [[ -n "$MATCH_SITE_TAG" ]]; then
    CLOUDFLARE_WEB_ANALYTICS_SITE_TAG="$MATCH_SITE_TAG"
  elif [[ -n "$BEACON_TOKEN" && -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
    CLOUDFLARE_WEB_ANALYTICS_SITE_TAG="$(
      curl -s "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/rum/site_info/list" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        | jq -r --arg token "$BEACON_TOKEN" '
          (.result // [])[]
          | select(.site_token == $token or (.snippet // "" | contains($token)))
          | .site_tag
        ' | head -1
    )"
  fi
fi

if [[ -z "${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG:-}" ]]; then
  echo
  echo "ERROR: ไม่พบ site_tag สำหรับ krujit.com" >&2
  echo "ตั้ง CLOUDFLARE_WEB_ANALYTICS_SITE_TAG หรือแก้ CLOUDFLARE_ACCOUNT_ID ให้ตรงบัญชีที่มี krujit.com" >&2
  exit 1
fi

echo
echo "=== 5) ดึง visits 7 วันล่าสุด site_tag=${CLOUDFLARE_WEB_ANALYTICS_SITE_TAG} ==="
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

GRAPHQL_RESULT="$(curl -s "https://api.cloudflare.com/client/v4/graphql" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary "$PAYLOAD")"
echo "$GRAPHQL_RESULT" | jq .

if echo "$GRAPHQL_RESULT" | jq -e '.errors | length > 0' >/dev/null; then
  echo
  echo "ERROR: GraphQL ล้มเหลว — token ต้องมีสิทธิ์ Account → Analytics → Read สำหรับ account นี้" >&2
  exit 1
fi

echo
echo "=== 6) รวม visits ทั้งหมดแบบ chunked (เหมือนตอน deploy) ==="
export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_WEB_ANALYTICS_SITE_TAG
export CLOUDFLARE_ANALYTICS_SINCE_YEAR="${CLOUDFLARE_ANALYTICS_SINCE_YEAR:-2025}"
bash "${SCRIPT_DIR}/fetch-cf-analytics.sh"
echo
cat "${SCRIPT_DIR}/../data/analytics.yaml"
