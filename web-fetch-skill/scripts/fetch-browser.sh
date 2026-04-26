#!/usr/bin/env bash
# fetch-browser.sh — Tier 3: Interactive browser via playwright-cli.
# Mirrors hermes-agent tools/browser_tool.py + tools/browser_supervisor.py.
#
# Handles pages that need JS interaction: cookie banners, lazy-loaded content,
# "verify you're human" checks, age gates, newsletter popups.
#
# Pipeline: navigate → dismiss dialogs → snapshot → detect & click blockers →
#           wait for content → extract text + images → output JSON
#
# Usage: ./scripts/fetch-browser.sh <url>
# Output: JSON with {url, title, content, images, method: "browser-tools"}
set -eu

URL="${1:-}"
if [ -z "$URL" ]; then
  echo '{"error":"No URL provided"}'
  exit 1
fi

export LC_ALL=C

# ── Helpers ─────────────────────────────────────────────────────────────────

# Extract a field from "Key: value" lines in playwright-cli output
extract_field() {
  local text="$1"
  local field="$2"
  echo "$text" | grep -i "$field:" 2>/dev/null | head -1 | sed "s/.*$field: *//" | tr -d '\r' || echo ""
}

# Find an element ref near a matching pattern in snapshot YAML
find_ref() {
  local snapshot="$1"
  local pattern="$2"
  echo "$snapshot" | grep -iE "$pattern" 2>/dev/null | head -1 | sed 's/.*\[ref=//; s/\].*//' || echo ""
}

# ── Auto-open browser ───────────────────────────────────────────────────────
echo >&2 "[web-fetch-browser] Ensuring browser is open..."

BROWSER_CHECK=$(playwright-cli --raw eval "1+1" 2>&1 || true)
if echo "$BROWSER_CHECK" | grep -qi "browser.*is not open"; then
  echo >&2 "[web-fetch-browser] Browser not open. Opening..."
  playwright-cli open 2>/dev/null || {
    echo '{"error":"Failed to open browser","url":"'"$URL"'"}'
    exit 1
  }
fi

# ── Step 1: Navigate (mirrors browser_navigate) ─────────────────────────────
echo >&2 "[web-fetch-browser] Navigating to $URL"
NAV_OUTPUT=$(playwright-cli goto "$URL" 2>&1 || true)

PAGE_URL=$(extract_field "$NAV_OUTPUT" "Page URL")
PAGE_TITLE=$(extract_field "$NAV_OUTPUT" "Page Title")

# Fallback if extraction failed (e.g. no "Page URL:" line)
if [ -z "$PAGE_URL" ]; then
  PAGE_URL="$URL"
fi

# ── Step 2: Auto-dismiss dialogs (mirrors browser_supervisor auto_dismiss) ──
echo >&2 "[web-fetch-browser] Checking for dialogs..."
for _ in 1 2 3; do
  DIALOG_RESULT=$(playwright-cli dialog-dismiss 2>&1 || true)
  if echo "$DIALOG_RESULT" | grep -qi "no dialog"; then
    break
  fi
  sleep 0.5
done

# ── Step 3: Take snapshot (mirrors browser_snapshot) ────────────────────────
echo >&2 "[web-fetch-browser] Taking page snapshot..."
SNAPSHOT=$(playwright-cli snapshot 2>&1 || echo "")

# ── Step 4: Auto-detect & click common blockers ─────────────────────────────
# Mirrors browser_tool.py's blocked_patterns detection + auto-interaction.

click_if_found() {
  local pattern="$1"
  local description="$2"
  local ref
  ref=$(find_ref "$SNAPSHOT" "$pattern")
  if [ -n "$ref" ]; then
    echo >&2 "[web-fetch-browser] $description — clicking $ref"
    playwright-cli click "$ref" 2>/dev/null || true
    sleep 1
    return 0
  fi
  return 1
}

# Cookie consent banners (most common blocker)
click_if_found '(accept all cookies|accept all|allow all cookies|allow all|agree and proceed|i agree|accept cookies|consent|got it|ok, got it)' "Cookie consent" || true

# Age verification gates
click_if_found '(i am.*1[89]|yes i am.*1[89]|i am an adult|enter site|continue to site)' "Age gate" || true

# "Verify you're human" / bot detection
click_if_found '(verify you are human|i am human|press and hold|click to verify)' "Bot check" || true

# Newsletter / signup popups — find close/dismiss button
click_if_found '(close|dismiss|skip|no thanks|not now|maybe later)' "Popup/overlay" || true

# GDPR / privacy banners
click_if_found '(accept essential|necessary only|reject all|reject non-essential|continue without accepting)' "GDPR banner" || true

# ── Step 5: Re-snapshot after interactions ──────────────────────────────────
echo >&2 "[web-fetch-browser] Re-snapshot after interactions..."
SNAPSHOT=$(playwright-cli snapshot 2>&1 || echo "")

# ── Step 6: Scroll to trigger lazy content (mirrors browser_scroll) ─────────
echo >&2 "[web-fetch-browser] Scrolling for lazy content..."
playwright-cli press PageDown 2>/dev/null || true
sleep 0.5
playwright-cli press PageDown 2>/dev/null || true
sleep 0.5
playwright-cli press End 2>/dev/null || true
sleep 1
playwright-cli press Home 2>/dev/null || true
sleep 0.5

# ── Step 7: Extract text content ────────────────────────────────────────────
echo >&2 "[web-fetch-browser] Extracting text content..."
CONTENT=$(playwright-cli --raw eval "document.body.innerText.substring(0, 20000)" 2>&1 || echo "")

# Clean surrounding quotes (playwright-cli --raw may quote the result)
CONTENT=$(echo "$CONTENT" | sed 's/^"//; s/"$//')

# Retry once if empty
if [ -z "$CONTENT" ] || [ "$CONTENT" = '""' ] || [ "$CONTENT" = "''" ]; then
  echo >&2 "[web-fetch-browser] Empty content, retrying after 2s..."
  sleep 2
  CONTENT=$(playwright-cli --raw eval "document.body.innerText.substring(0, 20000)" 2>&1 || echo "")
  CONTENT=$(echo "$CONTENT" | sed 's/^"//; s/"$//')
fi

# ── Step 8: Extract images (mirrors browser_get_images) ─────────────────────
echo >&2 "[web-fetch-browser] Extracting images..."
IMAGES_JS='JSON.stringify([...document.images].map(img => ({src: img.src, alt: img.alt || "", width: img.naturalWidth, height: img.naturalHeight})).filter(img => img.src && !img.src.startsWith("data:")).slice(0, 50))'
IMAGES_RAW=$(playwright-cli --raw eval "$IMAGES_JS" 2>&1 || echo "[]")
IMAGES_RAW=$(echo "$IMAGES_RAW" | sed 's/^"//; s/"$//')

# ── Step 9: Get console errors (mirrors browser_supervisor console ring) ────
echo >&2 "[web-fetch-browser] Collecting console errors..."
CONSOLE_OUTPUT=$(playwright-cli console error 2>&1 || echo "")
CONSOLE_COUNT=$(echo "$CONSOLE_OUTPUT" | grep -ci 'error\|exception' || echo "0")

# ── Step 10: Assemble JSON output ───────────────────────────────────────────
echo >&2 "[web-fetch-browser] Assembling output..."

TMPOUT=$(mktemp)
trap 'rm -f "$TMPOUT"' EXIT

cat > "$TMPOUT" << 'PYEOF'
import json, os

content = os.environ.get('BROWSER_CONTENT', '')
page_url = os.environ.get('BROWSER_PAGE_URL', '')
page_title = os.environ.get('BROWSER_PAGE_TITLE', '')
url = os.environ.get('BROWSER_URL', '')
images_raw = os.environ.get('BROWSER_IMAGES', '[]')
console_count = int(os.environ.get('BROWSER_CONSOLE_COUNT', '0'))

# Parse images JSON
try:
    images = json.loads(images_raw)
except (json.JSONDecodeError, TypeError):
    images = []

result = {
    'url': page_url or url,
    'title': page_title,
    'content': content[:20000],
    'method': 'browser-tools',
    'truncated': len(content) > 20000,
    'length': min(len(content), 20000),
    'images': images,
    'image_count': len(images),
    'console_errors': console_count,
}

# Add warnings for various conditions
warnings = []
if len(content) < 200:
    warnings.append("Very little text extracted — page may be image-heavy or blocked")
if console_count > 0:
    warnings.append(f"{console_count} console errors detected")
if not images:
    warnings.append("No images found on page")
if warnings:
    result['warnings'] = warnings

print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF

export BROWSER_CONTENT="$CONTENT"
export BROWSER_PAGE_URL="$PAGE_URL"
export BROWSER_PAGE_TITLE="$PAGE_TITLE"
export BROWSER_URL="$URL"
export BROWSER_IMAGES="$IMAGES_RAW"
export BROWSER_CONSOLE_COUNT="$CONSOLE_COUNT"

(cd /tmp && PYTHONIOENCODING=utf-8 exec uv run --no-project python "$TMPOUT")
