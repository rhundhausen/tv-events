# website

Hugo site, deployed to Cloudflare. Not built yet.

Reads events from the repo-level `data/` folder via a `module.mounts` entry (source `../data`, target `data`), so ingestion never writes into this tree. The `/bot` page for site owners who see the `tv-events` user agent lives at `content/bot.md`.
