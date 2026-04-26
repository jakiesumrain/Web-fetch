#!/usr/bin/env bash
# fetch-playwright.sh — Tier 2: Fetch JS-rendered web content via playwright-cli.
# Uses the Claude Code playwright-cli skill (already installed).
# Usage: ./scripts/fetch-playwright.sh <url>
# Output: JSON with {url, title, content}
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo '{"error":"No URL provided"}'
  exit 1
fi

# Auto-open browser if not already open
BROWSER_CHECK=$(playwright-cli --raw eval "1+1" 2>&1 || true)
if echo "$BROWSER_CHECK" | grep -qi "browser.*is not open"; then
  echo >&2 "[web-fetch-playwright] Browser not open. Opening..."
  playwright-cli open 2>/dev/null || {
    echo '{"error":"Failed to open playwright browser","url":"'"$URL"'"}'
    exit 1
  }
fi

# Navigate to page
NAV_OUTPUT=$(playwright-cli goto "$URL" 2>&1 || true)
PAGE_URL=$(echo "$NAV_OUTPUT" | grep -oP 'Page URL: \K\S+' | head -1 || echo "$URL")
PAGE_TITLE=$(echo "$NAV_OUTPUT" | grep -oP 'Page Title: \K.+' | head -1 || echo "")

# Extract rendered text
CONTENT=$(playwright-cli --raw eval "document.body.innerText.substring(0, 20000)" 2>&1 || echo "")

# Check if content is empty (page might not have loaded)
if [ -z "$CONTENT" ] || [ "$CONTENT" = '""' ] || [ "$CONTENT" = "''" ]; then
  echo >&2 "[web-fetch-playwright] Empty content, retrying after 2s..."
  sleep 2
  CONTENT=$(playwright-cli --raw eval "document.body.innerText.substring(0, 20000)" 2>&1 || echo "")
fi

# Clean up surrounding quotes
CONTENT=$(echo "$CONTENT" | sed 's/^"//; s/"$//')

TMPOUT=$(mktemp --suffix=.py)
trap 'rm -f "$TMPOUT"' EXIT

cat > "$TMPOUT" << 'PYEOF'
import json, sys, os

content = os.environ.get('PW_CONTENT', '')
page_url = os.environ.get('PW_PAGE_URL', '')
page_title = os.environ.get('PW_PAGE_TITLE', '')
url = os.environ.get('PW_URL', '')

result = {
    'url': page_url or url,
    'title': page_title,
    'content': content[:20000],
    'truncated': len(content) > 20000,
    'length': min(len(content), 20000),
}
print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF

export PW_CONTENT="$CONTENT"
export PW_PAGE_URL="$PAGE_URL"
export PW_PAGE_TITLE="$PAGE_TITLE"
export PW_URL="$URL"
(cd /tmp && PYTHONIOENCODING=utf-8 exec uv run --no-project python "$TMPOUT")
