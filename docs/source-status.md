# Source status

**Superseded.** [ingest-report.md](ingest-report.md) now covers every source, with the latest run's results. This page is the 2026-11-02 snapshot.

A snapshot of every source, from the dry run on 2026-11-02. It does not update by itself. Configuration lives in `sources.json`, and [sources.md](sources.md) explains each adapter. [ingest-report.md](ingest-report.md) has the results of that run.

**23 sources running:** 6 API (Ticketmaster), 7 API (tribe), 5 ICS feed, 5 Scrape. All succeeded in that run.

`Upcoming` counts events within 180 days after merging. An event reported by two sources counts for both. A lower priority number wins when sources report the same event.

## Running

| Source | Id | Type | Priority | Fetched | Upcoming | Last run | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ExtraMile Arena | `extramile-arena` | API (Ticketmaster) | 50 | 27 | 22 | 2026-11-02 18:18 | OK |
| Ford Idaho Center Arena | `ford-idaho-center-arena` | API (Ticketmaster) | 50 | 17 | 6 | 2026-11-02 18:18 | OK |
| Knitting Factory Boise | `knitting-factory-boise` | API (Ticketmaster) | 50 | 40 | 40 | 2026-11-02 18:19 | OK |
| Morrison Center | `morrison-center` | API (Ticketmaster) | 25 | 93 | 58 | 2026-11-02 18:19 | OK |
| Neurolux | `neurolux` | API (Ticketmaster) | 50 | 20 | 20 | 2026-11-02 18:19 | OK |
| Ticketmaster (metro-wide) | `ticketmaster-metro` | API (Ticketmaster) | 60 | 187 | 148 | 2026-11-02 18:19 | OK |
| Bogus Basin | `bogus-basin` | API (tribe) | 20 | 5 | 4 | 2026-11-02 18:15 | OK |
| Boise Mom | `boise-mom` | API (tribe) | 80 | 2080 | 1310 | 2026-11-02 18:18 | OK |
| Expo Idaho | `expo-idaho` | API (tribe) | 20 | 21 | 12 | 2026-11-02 18:18 | OK |
| Idaho Botanical Garden | `idaho-botanical-garden` | API (tribe) | 20 | 1 | 1 | 2026-11-02 18:18 | OK |
| Idaho Shakespeare Festival | `idaho-shakespeare-festival` | API (tribe) | 20 | 95 | 0 | 2026-11-02 18:18 | OK |
| Mike Brown Group | `mike-brown-group` | API (tribe) | 80 | 120 | 118 | 2026-11-02 18:19 | OK |
| Western Idaho Fair | `western-idaho-fair` | API (tribe) | 20 | 0 | 0 | 2026-11-02 18:19 | OK |
| Boise State Arts and Entertainment | `boise-state-arts` | ICS feed | 30 | 189 | 103 | 2026-11-02 18:18 | OK |
| Boise State Athletics | `boise-state-athletics` | ICS feed | 20 | 128 | 86 | 2026-11-02 18:18 | OK |
| College of Idaho Athletics | `college-of-idaho-athletics` | ICS feed | 20 | 118 | 75 | 2026-11-02 18:18 | OK |
| Idaho Steelheads | `idaho-steelheads` | ICS feed | 20 | 34 | 34 | 2026-11-02 18:18 | OK |
| Northwest Nazarene University Athletics | `nnu-athletics` | ICS feed | 20 | 101 | 61 | 2026-11-02 18:19 | OK |
| Boise Centre | `boise-centre` | Scrape | 20 | 1 | 1 | 2026-11-02 18:15 | OK |
| Idaho State Historical Society | `idaho-history` | Scrape | 20 | 5 | 5 | 2026-11-02 18:18 | OK |
| Indian Creek Plaza | `indian-creek-plaza` | Scrape | 20 | 5 | 5 | 2026-11-02 18:19 | OK |
| Visit Boise | `visit-boise` | Scrape | 80 | 12 | 10 | 2026-11-02 18:19 | OK |
| Visual Arts Collective | `visual-arts-collective` | Scrape | 20 | 6 | 2 | 2026-11-02 18:19 | OK |

## Built but not running

These adapters exist, and their tests pass against hand-written samples. None has run against the live API, because no credentials exist yet.

| Source | Needs | Status |
| --- | --- | --- |
| Eventbrite | EVENTBRITE_TOKEN, and organization or venue ids | Location search was removed in 2019, so the ids must be kept by hand |
| SeatGeek | SEATGEEK_CLIENT_ID | Documented geo filter. Mostly resale, so primary sellers outrank it |
| Songkick | SONGKICK_API_KEY, and a metro area id | Access is unconfirmed, and its docs could not be verified |
| Bandsintown | An approved app id, and artist names | Keyed by artist, so it can't list a venue's shows |

## Not available

| Site or platform | Reason |
| --- | --- |
| Meridian, Nampa, Zoo Boise, Opera Idaho, Visit Idaho, Trailhead, Boise Phil, AXS, Etix, Brown Paper Tickets | Refused or blocked automated requests, so they stay out |
| City of Eagle | robots.txt disallows its calendar feed |
| Discovery Center, Downtown Boise, Ballet Idaho, Boise Art Museum, Boise Contemporary Theater, Idaho Humanities, Stage Coach Theatre | No feed and no structured event data to read |
| The Olympic | API works but reported zero events, and it asks for 10 minutes between requests |
| Showclix, TicketLeap, Tix | Sold per organizer, so there is no local list without knowing each one |
| StubHub | Partner API only, and resale duplicates primary listings |
