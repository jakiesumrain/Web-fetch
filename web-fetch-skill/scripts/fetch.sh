#!/usr/bin/env bash
# fetch.sh — Progressive fallback orchestrator.
# Tries: curl → playwright-cli → browser-tools → mmx vision
# Usage: ./scripts/fetch.sh <url>
# Output: JSON with {url, title, content, images, method}
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo '{"error":"No URL provided","usage":"./scripts/fetch.sh <url>"}'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PYTHON_CMD="uv run --no-project python"

# Helper: run python via uv from /tmp to avoid project interference
python_run() {
  (cd /tmp && PYTHONIOENCODING=utf-8 $PYTHON_CMD "$@")
}

# Helper: extract a field from a JSON result safely
json_field() {
  local json="$1"
  local field="$2"
  echo "$json" | python_run -c "import sys,json; d=json.load(sys.stdin); print(d.get('$field',''))" 2>/dev/null || echo ""
}

# Helper: check if JSON has an error key
json_has_error() {
  local json="$1"
  local err
  err=$(echo "$json" | python_run -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null || echo "")
  [ -n "$err" ]
}

# Helper: check if content looks like an app shell (SPA that didn't render)
is_app_shell() {
  local content="$1"
  local len=${#content}
  if [ "$len" -lt 200 ]; then
    return 0
  fi
  # Only flag if page has an SPA root div AND very little visible text
  # (do NOT match <script> — every modern page has script tags)
  if echo "$content" | grep -qiE '<div id="root"|<div id="app"|loading\.\.\.|just a moment'; then
    # Strip HTML tags and check visible text length
    local text
    text=$(echo "$content" | sed 's/<[^>]*>//g' | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')
    if [ ${#text} -lt 300 ]; then
      return 0
    fi
  fi
  return 1
}

# Helper: rate-limit or auth-error detection from HTTP code
is_rate_limited() {
  local http_code="$1"
  case "$http_code" in
    429|403|401) return 0 ;;
    *) return 1 ;;
  esac
}

# Helper: curl connection-level failure (HTTP 0 = couldn't connect)
is_connection_failed() {
  local http_code="$1"
  [ "$http_code" = "0" ]
}

is_server_error() {
  local http_code="$1"
  case "$http_code" in
    5[0-9][0-9]) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Tier 1: curl ──────────────────────────────────────────────────────────
echo >&2 "[web-fetch] Tier 1: curl — $URL"
CURL_RESULT=$("$SCRIPT_DIR/fetch-curl.sh" "$URL" 2>/dev/null || echo '{"error":"curl failed"}')

_CURL_CONTENT=$(json_field "$CURL_RESULT" "content")
_CURL_LEN=${#_CURL_CONTENT}
_CURL_HTTP=$(json_field "$CURL_RESULT" "http_code")

if json_has_error "$CURL_RESULT"; then
  echo >&2 "[web-fetch] curl error: $(json_field "$CURL_RESULT" "error")"
elif is_connection_failed "$_CURL_HTTP"; then
  echo >&2 "[web-fetch] curl: connection failed (HTTP 0). Escalating..."
elif is_rate_limited "$_CURL_HTTP"; then
  echo >&2 "[web-fetch] curl: HTTP $_CURL_HTTP (rate limited). Escalating..."
elif is_server_error "$_CURL_HTTP"; then
  echo >&2 "[web-fetch] curl: HTTP $_CURL_HTTP (server error). Escalating..."
elif [ "$_CURL_LEN" -gt 0 ] && ! is_app_shell "$_CURL_CONTENT"; then
  echo "$CURL_RESULT" | python_run -c "import sys,json; d=json.load(sys.stdin); d['method']='curl'; print(json.dumps(d,indent=2,ensure_ascii=False))"
  exit 0
else
  echo >&2 "[web-fetch] curl: $_CURL_LEN chars, https_code=$_CURL_HTTP, app_shell=$(is_app_shell "$_CURL_CONTENT" && echo true || echo false). Escalating..."
fi

# ── Tier 2: playwright-cli ────────────────────────────────────────────────
echo >&2 "[web-fetch] Tier 2: playwright-cli — $URL"
PW_RESULT=$("$SCRIPT_DIR/fetch-playwright.sh" "$URL" 2>/dev/null || echo '{"error":"playwright-cli failed"}')

_PW_CONTENT=$(json_field "$PW_RESULT" "content")
_PW_LEN=${#_PW_CONTENT}

if json_has_error "$PW_RESULT"; then
  echo >&2 "[web-fetch] playwright-cli error: $(json_field "$PW_RESULT" "error")"
elif [ "$_PW_LEN" -gt 100 ]; then
  echo "$PW_RESULT" | python_run -c "import sys,json; d=json.load(sys.stdin); d['method']='playwright-cli'; print(json.dumps(d,indent=2,ensure_ascii=False))"
  exit 0
else
  echo >&2 "[web-fetch] playwright-cli: $_PW_LEN chars. Escalating..."
fi

# ── Tier 3: browser tools (interactive) ─────────────────────────────────────
echo >&2 "[web-fetch] Tier 3: browser-tools — $URL"
BW_RESULT=$("$SCRIPT_DIR/fetch-browser.sh" "$URL" 2>/dev/null || echo '{"error":"browser-tools failed"}')

_BW_CONTENT=$(json_field "$BW_RESULT" "content")
_BW_LEN=${#_BW_CONTENT}

if json_has_error "$BW_RESULT"; then
  echo >&2 "[web-fetch] browser-tools error: $(json_field "$BW_RESULT" "error")"
elif [ "$_BW_LEN" -gt 200 ]; then
  echo "$BW_RESULT" | python_run -c "import sys,json; d=json.load(sys.stdin); d['method']='browser-tools'; print(json.dumps(d,indent=2,ensure_ascii=False))"
  exit 0
else
  echo >&2 "[web-fetch] browser-tools: $_BW_LEN chars. Escalating..."
fi

# ── Tier 4: mmx vision (last resort) ──────────────────────────────────────
echo >&2 "[web-fetch] Tier 4: mmx vision — $URL"
MMX_RESULT=$("$SCRIPT_DIR/fetch-mmx.sh" "$URL" 2>/dev/null || echo '{"error":"mmx vision failed"}')

_MMX_CONTENT=$(json_field "$MMX_RESULT" "content")
_MMX_LEN=${#_MMX_CONTENT}

if json_has_error "$MMX_RESULT"; then
  echo >&2 "[web-fetch] mmx vision error: $(json_field "$MMX_RESULT" "error")"
elif [ "$_MMX_LEN" -gt 0 ]; then
  echo "$MMX_RESULT"
  exit 0
else
  echo >&2 "[web-fetch] mmx vision: $_MMX_LEN chars."
fi

echo >&2 "[web-fetch] All tiers failed."
echo '{"error":"All fetch tiers failed","url":"'"$URL"'"}'
