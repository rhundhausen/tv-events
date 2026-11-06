# Development

This page is for working on WeekendBoise. If you run a site and found this repo through the `WeekendBoise` user agent, see the [README](../README.md) instead.

Treasure Valley event aggregator. A nightly GitHub Actions workflow pulls events from venue, team, and community sources around Boise, Meridian, Nampa, Caldwell, and Eagle, and merges them into a single flat file. A Hugo site will publish the result; it is not built yet.

## How it works

1. `ingestion/sources.json` lists each source and the adapter that reads it (ICS feed, The Events Calendar REST API, a ticketing API, or, for sites with no feed, a `robots.txt`-respecting scraper). [ingest-report.md](ingest-report.md) shows every source, its state, and the last run's results.
2. `ingestion/scripts/Invoke-Ingest.ps1` runs every adapter, normalizes events to a common schema, dedupes across sources, and writes `data/events.json` (upcoming only). Past events roll into `data/archive/YYYY-MM.json`.
3. The workflow commits any changes to `data/`.

## Repo layout

```
.github/workflows/    ingest.yml (nightly ingest) and test.yml (Pester)
data/                 the contract between ingestion and the website
  events.json         upcoming events
  archive/            past events by month
  schema/             lookup tables: categories, tags, sizes, venue aliases
ingestion/
  scripts/            Invoke-Ingest, Publish-Data, Test-Sources, Test-Schema
    adapters/         one script per adapter type
    lib/              shared library
  tests/              Pester tests and fixtures
  schema/             JSON Schemas for events and sources
  sources.json        every source: running, waiting, ideas, ruled out
  .env.example.ps1    template for local API keys
website/              Hugo site (not built yet)
docs/                 schema, source reference, reports
```

## Running locally

Requires PowerShell 7.4 or later and Pester 6.0.0. Run everything from the repo root.

```powershell
. ./ingestion/.env.ps1                                       # load API keys, see below
./ingestion/scripts/Test-Sources.ps1                         # validate sources.json
./ingestion/scripts/Test-Schema.ps1                          # validate stored events
./ingestion/scripts/Invoke-Ingest.ps1 -NoWrite               # fetch and report, don't touch data/ (no link requests)
./ingestion/scripts/Invoke-Ingest.ps1 -NoLinkCheck           # a normal run without the link check
./ingestion/scripts/Invoke-Ingest.ps1 -NoWrite -Source idaho-steelheads   # one source
./ingestion/scripts/Invoke-Ingest.ps1 -CleanupOnly           # re-run dedupe and cleanup on stored data, no fetching
Invoke-Pester -Path ./ingestion/tests                        # run the tests
hugo server -s website                                       # the site, at http://localhost:1313
```

Every run drops events any source titles as canceled, and dedupes across sources (see `Merge-TvEvents` in `ingestion/scripts/lib/Dedupe.ps1`). `-CleanupOnly` applies a change to those rules to `data/events.json` and every archive month without a network request; add `-NoWrite` to see the counts first. A run that fetched also writes `data/meta.json` with the time of the last ingest, which the site shows.

### Link check

After the merge, every run checks the event links that are due (`ingestion/scripts/lib/Links.ps1`), so nobody clicks through to a page that's gone.

- **What breaks a link:** 404 and 410 break it the first night. Timeouts, 5xx, a host that doesn't resolve, and refused connections break it only on 2 nights in a row. 401, 403 and 429 never do, because they're a site turning away scripts (Ticketmaster answers 401), not a missing page.
- **When links are checked:** a link is checked the first night it appears, again 7 days after it last worked, and every night while it's failing, so a page that comes back gets its link back. Soonest events go first, within `-LinkBudgetSeconds` (default 900). Links left over count as working until a later night reaches them.
- **Politeness:** requests use the project User-Agent and follow each host's robots.txt; a disallowed path is never requested. Requests to one host are at least 1 second apart, or the host's Crawl-delay.
- **What a visitor sees:** an event whose link is broken first tries its other sources' links that are known to work. If none does, it gets `linkBroken: true`, and the site shows the title as plain text with the hover text "Information not available".
- **Where to look:** each run lists every link it checked in `out/links.json` and adds counts to `out/run.json`. The GitHub Actions run summary has a "Broken links" section grouped by source, new breaks first. The state is `data/links.json`, committed with the rest of `data/`.
- **Limits:** `-NoWrite` and `-NoLinkCheck` make no link requests but still apply what `data/links.json` already knows. With `-Source`, only that source's links are checked.

API keys are read from environment variables only. Copy `ingestion/.env.example.ps1` to `ingestion/.env.ps1` and fill in real values. `.env.ps1` and `.secrets.local.md` are gitignored; this repo is public, so never commit them. Sources whose key is missing fail with a warning and the rest still run. Raw per-source output and `run.json` go to `out/`, which is also gitignored.

## Nightly workflow

- `.github/workflows/ingest.yml` runs at midnight Boise time on the default branch. Cron is UTC, so it is scheduled at both 06:00 and 07:00 UTC, and a first job skips whichever one isn't midnight in Boise that day (daylight saving moves it). GitHub often starts scheduled runs late, so a scheduled run passes `-AsOf` with the scheduled midnight and the site's header reads 12:00 AM; a manual run records the time it ran. Run it by hand from Actions > ingest > Run workflow, with an optional `source` input to fetch one source. It uploads `out/` as an artifact, then `Publish-Data.ps1` commits `data/` as "WeekendBoise bot" and pushes to the branch the run started on. Only one ingest runs at a time. The commit has no `[skip ci]`, so Cloudflare deploys the new data; the test workflow doesn't run on it because GitHub never starts workflows from a push made with the workflow's `GITHUB_TOKEN`.
- **Deploying:** Cloudflare Workers Builds is connected to this repo as the `weekendboise` Worker, with `website/` as its root. `website/wrangler.jsonc` runs `build.sh`, which installs Hugo and builds the site, then the build output in `website/public` is deployed. Every push to `main` deploys, including the nightly data commit. A deploy shows as the "Workers Builds: weekendboise" check on the commit in GitHub. Cloudflare skips any commit whose message contains `[skip ci]`, so leave it out of commits that should reach the site.
- `.github/workflows/test.yml` runs the Pester tests on every push and pull request and uploads `testResults.xml`.

Create these repository secrets (Settings > Secrets and variables > Actions). Only `TICKETMASTER_KEY` is needed today; the others are for sources that are built but not running yet. An unset secret reaches the scripts as empty.

| Secret | Used by |
| --- | --- |
| `TICKETMASTER_KEY` | Ticketmaster (running) |
| `BANDSINTOWN_APP_ID` | Bandsintown (needs an approved app id) |
| `EVENTBRITE_TOKEN` | Eventbrite (disabled) |
| `SEATGEEK_CLIENT_ID` | SeatGeek (disabled) |
| `SONGKICK_API_KEY` | Songkick (disabled) |

First-time setup in the GitHub UI is in [github-setup.md](github-setup.md).

## Adding a source

Add an entry to `ingestion/sources.json`. An idea needs only a `displayName`; a source ingest runs needs a `name`, its adapter's fields, and `status: running`. If an existing adapter fits (most WordPress event calendars and ICS feeds do), that's all. See [sources.md](sources.md) for each adapter's fields and how to find a feed. Otherwise add a script under `ingestion/scripts/adapters/` that emits events in the [common schema](schema.md), plus a fixture under `ingestion/tests/fixtures/`.

Prefer official APIs and published feeds over scraping. Adapters identify themselves in the User-Agent and keep request rates low.

## Status

Phase 1: ingestion and the nightly workflow. The website and notifications come later.

## Built with

Designed and built with [Claude Code](https://claude.com/claude-code) and [Claude](https://claude.ai). The source list, architecture, and adapters were developed collaboratively; mistakes are mine.

## License

[Unlicense](../LICENSE). Event data belongs to the venues and organizers who publish it.
