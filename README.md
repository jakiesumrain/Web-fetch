# Web Fetch Skill

A progressive content pipeline for fetching web pages — starts fast with curl, escalates to Playwright (JS rendering), browser automation (interactive), and mmx vision (image analysis) as needed.

## Usage

```bash
./web-fetch-skill/scripts/fetch.sh "https://example.com"
```

## Pipeline Tiers

| Tier | Tool | When |
|------|------|------|
| 1 | curl | Static HTML, APIs |
| 2 | playwright-cli | SPAs, JS-rendered pages |
| 3 | browser tools | Cookie walls, login flows |
| 4 | mmx vision | Image-heavy, PDFs |

## Output

JSON with `url`, `title`, `content`, `method`, `truncated`, and `length`.
