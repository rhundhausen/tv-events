# website

Hugo site, to be deployed to Cloudflare. A single page lists upcoming events in a grid, 50 per page, with search and filters.

Reads events from the repo-level `data/` folder via a `module.mounts` entry (source `../data`, target `data`), so ingestion never writes into this tree. `ingestion/sources.json` is mounted the same way as `data/sources.json`, for the `/sources/` page (every running source, with its upcoming event count linking to the grid filtered by `?source=<name>`) and the header count. The `/bot` page for site owners who see the `tv-events` user agent will live at `content/bot.md`.

## Run it

From the repo root (Hugo extended 0.156 or later):

```powershell
hugo server -s website          # http://localhost:1313, rebuilds on change
hugo -s website --minify        # builds to website/public/ (gitignored)
```

## How it works

- `layouts/home.html` reads `events.json` and the category and size lookups at build time, and writes a slimmer copy (short keys, only the fields the page shows) to `data/events.<hash>.json`.
- `assets/js/app.js` loads that file and does the rest in the browser: search (all words must match, accents ignored), the date, city, size, and category filters, sorting, and paging. The filters are kept in the URL, so a filtered view can be shared or bookmarked.
- `assets/css/site.css` holds the styles. Colors are CSS variables with a dark set for `prefers-color-scheme: dark`. Below 760px wide, each row becomes a card.
- No external scripts, fonts, or CDNs. Event text comes from outside sources, so the script only ever sets it with `textContent`.
