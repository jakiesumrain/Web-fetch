# web-fetch

An agentic skill for fetching web page content. Designed to be invoked by AI agents (Claude Code, OpenClaw, Hermes Agent, OpenCode) when they need to retrieve content from a URL.

## Invocation

Agents should call this skill when the user asks to fetch, scrape, or read content from a web page. The skill auto-selects the best method via a progressive fallback chain:

1. **curl** — static HTML (fastest, no JS)
2. **playwright-cli** — JS-rendered pages (SPAs, dynamic sites)
3. **browser tools** — interactive (cookie walls, login flows, lazy loading)
4. **mmx vision** — screenshot analysis (images, PDFs — last resort)

Escalation triggers: HTTP errors (429/403/5xx), empty content, app shell detection, tool failure.

## SKILL.md Registration

Register in an agent's SKILL.md:

```yaml
---
name: web-fetch
description: Fetch web page content using a progressive fallback chain — curl (fast, no JS) → playwright-cli (JS-rendered) → browser tools (interactive) → mmx vision (image analysis). No paid API keys needed.
tags: [web, fetch, scrape, curl, playwright, mmx, browser-automation]
---

When the user asks to fetch a URL or scrape web content, use:
`./scripts/fetch.sh "https://example.com"`

See `SKILL.md` for full details.
```

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
