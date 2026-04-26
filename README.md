# web-fetch

Fetch content from any web page using a progressive fallback chain. Call from your skill's SKILL.md or directly via scripts.

## Usage

```bash
./scripts/fetch.sh "https://example.com"
```

Always use `fetch.sh` — it handles the full fallback chain:

1. **curl** — static HTML, fast. Good for APIs, markdown, docs.
2. **playwright-cli** — JS-rendered. Good for SPAs, dynamic sites.
3. **browser tools** — interactive. Good for cookie walls, login flows, lazy-loading.
4. **mmx vision** — VLM screenshot analysis. Last resort for images, PDFs.

Escalation happens automatically on: HTTP errors (429/403/5xx), empty/short content, app shell detection (bare `<div id="root">`), or tool failure.

## Output

```json
{
  "url": "https://final-url",
  "title": "Page Title",
  "content": "Extracted text...",
  "method": "curl|playwright-cli|browser-tools|mmx-vision",
  "truncated": false,
  "length": 12345
}
```

On error: `{"error": "message", "url": "https://..."}`

## Individual Tiers

- `./scripts/fetch-curl.sh <url>` — curl only
- `./scripts/fetch-playwright.sh <url>` — playwright only
- `./scripts/fetch-browser.sh <url>` — interactive browser with auto-dismiss, cookie consent handling, scrolling, console error collection
- `./scripts/fetch-mmx.sh <url>` — mmx vision screenshot analysis
