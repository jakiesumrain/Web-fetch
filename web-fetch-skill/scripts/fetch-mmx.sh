#!/usr/bin/env bash
# fetch-mmx.sh — Tier 4: Last-resort vision-based page analysis via mmx-cli.
# Use when curl and playwright-cli both failed to extract meaningful text
# (e.g. image-heavy pages, PDF viewers, CAPTCHA gates).
# Usage: ./scripts/fetch-mmx.sh <url>
# Output: JSON with {url, title, content, method: "mmx-vision"}
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo '{"error":"No URL provided"}'
  exit 1
fi

SCREENSHOT_FILE=$(mktemp /tmp/web-fetch-screenshot-XXXXXX.png)
trap 'rm -f "$SCREENSHOT_FILE"' EXIT

# Auto-open browser if not already open
BROWSER_CHECK=$(playwright-cli --raw eval "1+1" 2>&1 || true)
if echo "$BROWSER_CHECK" | grep -qi "browser.*is not open"; then
  echo >&2 "[web-fetch-mmx] Browser not open. Opening..."
  playwright-cli open 2>/dev/null || true
fi

# Navigate and screenshot via playwright-cli
playwright-cli goto "$URL" 2>/dev/null || true
PAGE_TITLE=$(playwright-cli --raw eval "document.title" 2>/dev/null | sed 's/^"//; s/"$//' || echo "")
playwright-cli screenshot --filename="$SCREENSHOT_FILE" 2>/dev/null || true

# Use mmx vision to extract text from the screenshot
CONTENT=$(mmx vision describe --image "$SCREENSHOT_FILE" \
  --prompt "Extract ALL text visible in this image. Also describe the page layout, any buttons, links, and what this page is about. Return everything as plain text." \
  --quiet 2>/dev/null || echo "")

CONTENT_LEN=${#CONTENT}

(cd /tmp && PYTHONIOENCODING=utf-8 uv run --no-project python -c "
import json, os

result = {
    'url': os.environ.get('URL', ''),
    'title': os.environ.get('PAGE_TITLE', ''),
    'content': os.environ.get('CONTENT', '')[:20000],
    'method': 'mmx-vision',
    'truncated': len(os.environ.get('CONTENT', '')) > 20000,
    'length': min(len(os.environ.get('CONTENT', '')), 20000),
    'warning': 'Extracted via image analysis — text may contain transcription errors'
}
print(json.dumps(result, indent=2, ensure_ascii=False))
")
