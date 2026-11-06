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
./ingestion/scripts/Invoke-Ingest.ps1 -NoWrite               # fetch and report, don't touch data/
./ingestion/scripts/Invoke-Ingest.ps1 -NoWrite -Source idaho-steelheads   # one source
./ingestion/scripts/Invoke-Ingest.ps1 -CleanupOnly           # re-run dedupe and cleanup on stored data, no fetching
Invoke-Pester -Path ./ingestion/tests                        # run the tests
hugo server -s website                                       # the site, at http://localhost:1313
```

Every run drops events any source titles as canceled, and dedupes across sources (see `Merge-TvEvents` in `ingestion/scripts/lib/Dedupe.ps1`). `-CleanupOnly` applies a change to those rules to `data/events.json` and every archive month without a network request; add `-NoWrite` to see the counts first. A run that fetched also writes `data/meta.json` with the time of the last ingest, which the site shows.

API keys are read from environment variables only. Copy `ingestion/.env.example.ps1` to `ingestion/.env.ps1` and fill in real values. `.env.ps1` and `.secrets.local.md` are gitignored; this repo is public, so never commit them. Sources whose key is missing fail with a warning and the rest still run. Raw per-source output and `run.json` go to `out/`, which is also gitignored.

## Nightly workflow

- `.github/workflows/ingest.yml` runs at midnight Boise time on the default branch. Cron is UTC, so it is scheduled at both 06:00 and 07:00 UTC, and a first job skips whichever one isn't midnight in Boise that day (daylight saving moves it). GitHub often starts scheduled runs late, so a scheduled run passes `-AsOf` with the scheduled midnight and the site's header reads 12:00 AM; a manual run records the time it ran. Run it by hand from Actions > ingest > Run workflow, with an optional `source` input to fetch one source. It uploads `out/` as an artifact, then `Publish-Data.ps1` commits `data/` as "WeekendBoise bot" with `[skip ci]` and pushes to the branch the run started on. Only one ingest runs at a time.
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
