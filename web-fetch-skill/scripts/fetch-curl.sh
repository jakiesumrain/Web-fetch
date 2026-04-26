#!/usr/bin/env bash
# fetch-curl.sh — Tier 1: Fetch web content using curl.
# Usage: ./scripts/fetch-curl.sh <url>
# Output: JSON with {url, title, content, headers}
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo '{"error":"No URL provided"}'
  exit 1
fi

# Security: block URLs with embedded secrets (API keys, tokens)
if echo "$URL" | grep -qiE '(sk-[a-zA-Z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36,})'; then
  echo '{"error":"Blocked: URL appears to contain an API key or token"}'
  exit 1
fi

# Fetch with redirect follow and modern UA
TMPFILE=$(mktemp)
TMPHEADERS=$(mktemp)
TMPOUT=$(mktemp --suffix=.py)
trap 'rm -f "$TMPFILE" "$TMPHEADERS" "$TMPOUT"' EXIT

# Single curl request: body + headers + http_code + effective URL
CURL_META=$(curl -sL -o "$TMPFILE" -D "$TMPHEADERS" \
  -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
  --max-time 30 \
  -w "%{http_code}\n%{url_effective}" \
  "$URL" 2>/dev/null || printf "000\n%s" "$URL")

HTTP_CODE=$(echo "$CURL_META" | head -1)
FINAL_URL=$(echo "$CURL_META" | tail -1)

# Extract content type
CONTENT_TYPE=$(grep -i '^content-type:' "$TMPHEADERS" 2>/dev/null | sed 's/.*: //' | tr -d '\r' || echo "unknown")

# Extract title from HTML
TITLE=$(grep -o '<title>[^<]*</title>' "$TMPFILE" 2>/dev/null | sed 's/<title>//; s/<\/title>//' | head -1 || echo "")

# Write Python script to temp file to avoid "Argument list too long" on Windows
cat > "$TMPOUT" << 'PYEOF'
import json, sys

with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

http_code = sys.argv[2]
content_type = sys.argv[3]
title = sys.argv[4]
final_url = sys.argv[5]

result = {
    'url': final_url,
    'title': title,
    'content': content[:20000],  # cap at 20K chars
    'content_type': content_type,
    'http_code': int(http_code) if http_code.isdigit() else 0,
    'truncated': len(content) > 20000,
    'length': min(len(content), 20000),
}
print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF

(cd /tmp && PYTHONIOENCODING=utf-8 exec uv run --no-project python "$TMPOUT" "$TMPFILE" "$HTTP_CODE" "$CONTENT_TYPE" "$TITLE" "$FINAL_URL")
