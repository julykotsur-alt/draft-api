#!/usr/bin/env bash
# Jira gate for the API regression workflow.
#
# 1. Verifies a real Jira login via GET /rest/api/3/myself.
#    Jira answers searches anonymously (HTTP 200, 0 issues) when credentials are
#    missing or wrong, so a search result alone cannot prove that the gate works.
# 2. Searches tickets via POST /rest/api/3/search/jql.
# 3. Writes the tickets with links to the job summary and sets the outputs
#    has_tickets (true/false) and ticket_count.
#
# Env: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_JQL.
# Exits non-zero (failing the run) on missing configuration, failed login or a failed search.
set -euo pipefail

: "${GITHUB_OUTPUT:=/dev/null}"
: "${GITHUB_STEP_SUMMARY:=/dev/stdout}"

summary() { printf '%s\n' "$@" >> "$GITHUB_STEP_SUMMARY"; }
fail() {
  echo "::error title=Jira gate::$1"
  summary "### ❌ Jira gate failed" "" "$1" ""
  exit 1
}

missing=()
[ -n "${JIRA_BASE_URL:-}" ] || missing+=("JIRA_BASE_URL (repository variable)")
[ -n "${JIRA_EMAIL:-}" ] || missing+=("JIRA_EMAIL (repository secret)")
[ -n "${JIRA_API_TOKEN:-}" ] || missing+=("JIRA_API_TOKEN (repository secret)")
[ -n "${JIRA_JQL:-}" ] || missing+=("JIRA_JQL")
if [ ${#missing[@]} -gt 0 ]; then
  list="$(printf '%s, ' "${missing[@]}")"
  fail "Jira gate is not configured. Missing: ${list%, }. The regression was not run."
fi

JIRA_BASE_URL="${JIRA_BASE_URL%/}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- 1. Login check -----------------------------------------------------------
code="$(curl -sS -m 30 -o "$tmp/me.json" -w '%{http_code}' \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -H 'Accept: application/json' \
  "$JIRA_BASE_URL/rest/api/3/myself")" \
  || fail "Could not reach $JIRA_BASE_URL/rest/api/3/myself."

if [ "$code" != "200" ]; then
  fail "Jira login failed: GET /rest/api/3/myself returned HTTP $code. Check that JIRA_EMAIL is the email of the Atlassian account that owns JIRA_API_TOKEN and that the token is valid."
fi

account_id="$(jq -r '.accountId // empty' "$tmp/me.json" 2>/dev/null || true)"
active="$(jq -r '.active // false' "$tmp/me.json" 2>/dev/null || true)"
display_name="$(jq -r '.displayName // "unknown"' "$tmp/me.json" 2>/dev/null || true)"

if [ -z "$account_id" ]; then
  fail "Jira login check returned HTTP 200 without an accountId: this is anonymous access, not a real login. Searches would silently return 0 tickets."
fi
if [ "$active" != "true" ]; then
  fail "Jira account '$display_name' is not active."
fi
echo "Authenticated to Jira as: $display_name"

# --- 2. Ticket search ---------------------------------------------------------
jq -n --arg jql "$JIRA_JQL" \
  '{jql: $jql, fields: ["summary", "status", "issuetype"], maxResults: 100}' > "$tmp/query.json"

code="$(curl -sS -m 30 -o "$tmp/search.json" -w '%{http_code}' \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -X POST --data @"$tmp/query.json" \
  "$JIRA_BASE_URL/rest/api/3/search/jql")" \
  || fail "Could not reach $JIRA_BASE_URL/rest/api/3/search/jql."

if [ "$code" != "200" ]; then
  details="$(jq -r '[.errorMessages[]?, (.errors // {} | to_entries[] | "\(.key): \(.value)")] | join("; ")' "$tmp/search.json" 2>/dev/null || true)"
  fail "Jira search failed: POST /rest/api/3/search/jql returned HTTP $code. ${details}"
fi

count="$(jq '.issues | length' "$tmp/search.json")"
is_last="$(jq -r 'if has("isLast") then .isLast else true end' "$tmp/search.json")"

summary "### Jira gate" "" \
  "Signed in as **$display_name**." "" \
  "JQL: \`$JIRA_JQL\`" ""

if [ "$count" -gt 0 ]; then
  more=""
  [ "$is_last" = "true" ] || more=" (first page)"
  summary "Found **$count** ticket(s)$more, running the regression:" "" \
    "| Ticket | Type | Status | Summary |" \
    "|---|---|---|---|"
  jq -r --arg base "$JIRA_BASE_URL" '
    .issues[]
    | "| [\(.key)](\($base)/browse/\(.key)) | \(.fields.issuetype.name // "") | \(.fields.status.name // "") | \((.fields.summary // "") | gsub("\\|"; "\\|")) |"
  ' "$tmp/search.json" >> "$GITHUB_STEP_SUMMARY"
  summary ""
  jq -r --arg base "$JIRA_BASE_URL" '.issues[] | "  \(.key)  \(.fields.status.name // "")  \($base)/browse/\(.key)"' "$tmp/search.json"
  echo "has_tickets=true" >> "$GITHUB_OUTPUT"
else
  summary "No matching tickets: **the regression is skipped** for this run." ""
  echo "::notice title=Jira gate::No tickets match the JQL; the regression is skipped."
  echo "has_tickets=false" >> "$GITHUB_OUTPUT"
fi
echo "ticket_count=$count" >> "$GITHUB_OUTPUT"
echo "Tickets found: $count"
