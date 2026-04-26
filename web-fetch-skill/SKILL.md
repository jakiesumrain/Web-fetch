---
name: web-fetch
description: Fetch web page content using a progressive fallback chain — curl (fast, no JS) → playwright-cli (JS-rendered) → browser tools (interactive) → mmx vision (image analysis). No paid API keys needed.
version: 2.1.0
author: Hermes Agent
tags: [web, fetch, scrape, curl, playwright, mmx, browser-automation]
requires: [curl, playwright-cli, mmx]
---

# Web Fetch — Progressive Content Pipeline

Fetch content from any web page using a fallback chain that escalates capability only when needed. Each tier trades speed for rendering fidelity.

```
Tier 1: curl            → fastest, no JS.        Good for: APIs, static HTML, markdown
Tier 2: playwright-cli  → headless Chromium.      Good for: SPAs, dynamic JS sites
Tier 3: browser tools   → full interactive.       Good for: cookie walls, lazy-loaded, login flows
Tier 4: mmx vision      → VLM image analysis.     Last resort: image-heavy pages, PDFs
```

## Quick Start

```bash
# Automatic fallback chain (curl → playwright-cli → mmx)
./scripts/fetch.sh "https://example.com"
```

**Always use `fetch.sh`.** It calls each tier in order and automatically escalates when a tier fails (empty content, rate limit, app shell, server error). Do not call individual tier scripts unless you have a specific reason.

## How Fallback Works

`fetch.sh` tries each tier in sequence. It escalates to the next tier when:

| Condition | What it means |
|-----------|---------------|
| HTTP 0 (no connection) | Curl couldn't reach the server — escalate |
| HTTP 429/403/401 | Rate limited or blocked — escalate |
| HTTP 5xx | Server error — escalate |
| Empty or very short content | Page didn't render — escalate |
| Content looks like an app shell (`<div id="root">`, `<script>`-heavy) | SPA needs JS — escalate |
| Tier script exits with error | Tool unavailable — escalate |

Site-specific notes:
- **GitHub**: API rate-limits aggressively without auth. If curl gets HTTP 403/429, `fetch.sh` auto-escalates to playwright-cli.
- **X/Twitter**: Login wall blocks all automated browsers. Use `xurl` skill instead.

## Output Format

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

---

## Advanced: Individual Tiers

Use these only when you know exactly which tier you need (e.g., testing, forcing a specific method).

### Tier 1: curl (Static Content)

```bash
./scripts/fetch-curl.sh "https://example.com/page"
```

Good for: APIs, static HTML, markdown.

### Tier 2: playwright-cli (JS-Rendered Content)

```bash
./scripts/fetch-playwright.sh "https://example.com"
```

Uses playwright-cli under the hood:
```
playwright-cli goto <url>
playwright-cli --raw eval "document.body.innerText.substring(0, 20000)"
```

### Tier 3: Browser Tools (Interactive)

```bash
./scripts/fetch-browser.sh "https://example.com"
```

Full interactive browser inspired by hermes-agent's `tools/browser_tool.py` and `tools/browser_supervisor.py`. The script automatically:

1. **Navigates** to the page (mirrors `browser_navigate`)
2. **Dismisses dialogs** — auto-dismisses alert/confirm/prompt dialogs (mirrors `browser_supervisor.py` auto_dismiss policy)
3. **Takes accessibility snapshot** — gets page structure with element refs (mirrors `browser_snapshot`)
4. **Detects & clicks common blockers** — cookie consent banners, age verification gates, newsletter popups, GDPR prompts, bot detection pages
5. **Scrolls for lazy content** — PageDown/End/Home to trigger lazy-loaded images and infinite scroll
6. **Extracts text** via `document.body.innerText` (mirrors Tier 2 extraction)
7. **Extracts images** — `src`, `alt`, dimensions from all visible `<img>` elements (mirrors `browser_get_images`)
8. **Collects console errors** — error/exception count from the console (mirrors `browser_supervisor.py` console ring buffer)

Output includes `images` array and `warnings` for low-text pages or console errors.

Manual interaction (when auto-handling isn't enough):
```bash
playwright-cli snapshot           # see element refs
playwright-cli click e15          # click by ref
playwright-cli fill e7 "query"    # fill input fields
playwright-cli press Enter        # submit forms
playwright-cli --raw eval "document.body.innerText"
```

Good for: Interactive pages, login flows, cookie-walled sites, lazy-loaded SPAs.

### Tier 4: mmx Vision (Last Resort)

```bash
./scripts/fetch-mmx.sh "https://example.com"
```

The script:
1. Takes a screenshot via playwright-cli
2. Feeds it to `mmx vision describe` for text extraction
3. Returns extracted text with a warning that it's vision-derived

Good for: Image-heavy pages, PDFs, CAPTCHA gates.
