# Emmett sources, nightly link check, cost tiers, and a 3-line phone row

Date: 2026-11-05. Status: draft for the owner's review.

Four changes, built together because they land in the same nightly run and the same grid:

1. Two new Emmett-area sources.
2. A nightly check that every event link still works.
3. A rough cost tier (Free, $, $$, $$$) on every event where one can be told or guessed, with a filter.
4. A phone layout that keeps each event to 3 lines.

## Why

The site is meant to be the one place to see what's on in the Treasure Valley. Emmett has almost no coverage yet. A link that 404s is embarrassing and makes the whole listing look stale, so the owner wants broken links caught before a visitor finds them. Cost is the first thing many people want to know after date and place. The phone card currently spends a 4th line on the city alone.

## Goals

- Events from the Gem County Chamber calendar and the Eventbrite "Emmett" page appear on the site.
- No event title on the site links to a page that is known to be gone.
- The owner can see, each morning, which links broke and from which source.
- Most events show a cost tier, even if it is a rough guess. Clicking through gives the real price.
- Visitors can filter by cost.
- On a phone, each event is 3 lines: date line, title, "City | Venue" line.

## Non-goals

- Showing exact prices. Only the tier is stored and shown.
- Other Eventbrite towns, or the Caldwell, Meridian and Nampa chamber calendars, even though they run on the same platforms. They can follow later using the same code.
- Emails or other alerts for broken links. The log is enough for now.
- Changes to the existing `eventbrite` API adapter (status `ready`).

## Anti-goals (would be a failure even if it technically works)

- Stripping links that work. A site that blocks bots (Ticketmaster often answers scripts with 403), a slow server, or a bad hour on someone's host must not remove a link.
- Hammering small sites. About 2,350 event links exist today and about 1,150 of them are on boisemom.com. The check must not hit every link every night.
- A cost tier that looks authoritative when it is a guess for an expensive event shown as Free. When signals are weak, leave the tier blank.
- Breaking robots.txt rules or the project's polite crawling habits.

## 1. New sources

Both follow the existing conventions in `ingestion/sources.json` (robotsChecked date, notes, priority, Terms not read) and get fixtures and Pester tests like the other adapters.

### gem-county-chamber (business.emmettidaho.com)

- **Calendar:** `https://business.emmettidaho.com/events/calendar/`. This is the Gem County Chamber of Commerce (emmettidaho.com is its WordPress site). The calendar is ChamberMaster / GrowthZone.
- **robots.txt (checked 2026-11-05):** allows `/events/calendar/` and `/events/details/...`. It disallows `/*?rendermode=*`, `/events/search` and `/events/searchscroll`. There is no crawl delay.
- **What the pages have:** the month calendar page links to about 70 events for November 2026, each at `/events/details/<slug>-<id>?calendarMonth=...`. Each detail page has schema.org microdata (`itemprop="startDate"`, `endDate`, `location`, `name`) and an "add to calendar" link at `/events/addtocalendar/<slug>-<id>?format=ICal`, which robots.txt allows.
- **How to read it (builder's choice of detail):** a new `scrapeMode` (suggested name `chambermaster`) in `scrape.ps1`. It reads the calendar for the current month and the next 2 months, collects the detail links (drops the `calendarMonth` query), and reads each event from its iCal link using the existing ICS parsing, or from the microdata if that turns out simpler. Pause about 1 second between requests.
- **Settings:** city Emmett, category community-civic with inferCategory, priority 20 (same as the other city and chamber calendars).
- **Filtering (my call):** many entries are weekly church services and recurring classes ("Worship Service", "Line Dancing", "Shotokan Karate"). Use `excludeTitlePattern` to drop worship services, meetings and closures. Keep classes and everything else. The builder tunes the pattern after seeing a real month.

### eventbrite-emmett (Eventbrite search page)

- **Page:** `https://www.eventbrite.com/d/id--emmett/events/`. robots.txt (checked 2026-11-05) does not disallow `/d/` pages. The `x`, `id` and `calendar` query parameters it does disallow are not needed.
- **What the page has:** the page's `window.__SERVER_DATA__` JSON has `buckets[].events[]`, with `name`, `start_date`, `start_time`, `end_date`, `end_time`, `timezone`, `url`, `is_cancelled`, `is_online_event`, `summary` and `primary_venue.address`. The JSON-LD on the page has dates only, with no times, so use `__SERVER_DATA__`.
- **What's in it today:** 16 events on 2026-11-05. None were in Emmett itself; they were in Meridian, Garden City, Caldwell, Eagle, Nampa and Boise, and 8 had no city. Eventbrite's "near Emmett" covers the wider valley. Those are still wanted. The existing dedupe merges any that other sources already have.
- **Skip:** online events, canceled events, and events whose address is outside Idaho.
- **Price:** the listing has no price. The builder checks whether each event's `/e/` page has schema.org `offers` with a price or a free flag. If it does, read it (16 extra requests at about 1 second apart is fine). If not, Eventbrite events fall back to the cost rules in section 3.
- **How:** a new adapter (suggested name `eventbrite-search`), separate from the API adapter. The page path (`id--emmett`) is a setting in sources.json, so other towns can be added later without code. Follow page 2 and beyond if the page offers it.
- **Settings:** priority 70 (the same as the Eventbrite API entry, so venue and city sources win the dedupe), inferCategory, city from the venue address.

## 2. Nightly link check

### What the owner asked for

- A broken link is recorded in a log file.
- The event stays on the site. Its title is not a link, and hovering over it says "Information not available".

### What counts as broken

- **Broken:** HTTP 404 or 410, or a redirect chain that ends in 404 or 410.
- **Not broken, and never removes a link:** 401, 403, 429 and other "go away, bot" answers. A site that blocks scripts says nothing about whether the page exists.
- **Not broken on the first try:** timeouts, 5xx, a host that doesn't resolve, and refused connections. A link is marked broken only after it fails this way on 2 nights in a row, because a single failure looks just like a host having a bad hour (my call).
- **Not checked:** a URL whose path robots.txt disallows for our user agent. `lib/Scrape.ps1` parses robots.txt but nothing caches it, so the link check fetches robots.txt once per host per run and reuses `Get-TvRobotsGroup` and `Test-TvRobotsAllowed`.
- Requests use GET (some servers mishandle HEAD) with the project User-Agent from `Get-TvUserAgent`. They follow redirects and read only enough of the body to finish the request.

### When links are checked (my call)

- A link is checked the first night it appears.
- A link that worked is checked again 7 days after its last check.
- A broken link is checked every night, so a page that comes back gets its link back.
- Requests to the same host are at least 1 second apart, or the host's robots.txt crawl delay if that is longer.
- Each night has a time budget (suggested: 15 minutes for the check). Links left over carry to the next night, events happening soonest first. The workflow's 60-minute timeout must not be at risk.
- The first night will not get through all 2,350 links. That's expected. Until a link has been checked, it is treated as working.

### Where results live

- **`data/links.json`** (new, committed nightly with the rest of `data/`): one entry per URL with the last status, `checkedAt`, `brokenSince`, and the consecutive failure count. This drives the schedule and gives a history in git.
- **The event record:** a new optional field (suggested `linkBroken: true`) in `event.schema.json`.
- **Fallback to another source's link (my call):** the schedule above covers each event's own `url` (about 2,350 today). Other `sources[].url` links are checked only when an event's own link is found broken. Before the event is marked broken, each of its other source links that differs is checked that same night (same politeness rules), and the first one that works becomes the event's `url`. A link counts as working only if it was actually checked and worked, never because it hasn't been checked. These checks are recorded in `links.json` like any other.
- **The log the owner reads:**
  - `out/links.json` in the run's uploaded artifact, listing every link checked that night with its result.
  - A short "Broken links" section in the GitHub Actions run summary (`$GITHUB_STEP_SUMMARY`), grouped by source: event title, date, link, and what went wrong. New breaks are listed first. A source with many broken links usually means an adapter problem, which is why the list is grouped.
  - Counts in `out/run.json`.

### Running it

- It runs in `Invoke-Ingest.ps1` after the merge, on every normal run. A `-NoLinkCheck` switch skips it for quick local runs. `-CleanupOnly` never checks links.
- With `-Source`, only that source's links are checked.
- Link results from `data/links.json` still apply to events from sources that weren't fetched that night.

## 3. Cost tiers

### Tiers

| Tier | Meaning |
|---|---|
| Free | $0 |
| $ | under $25 |
| $$ | $25 to $99 |
| $$$ | $100 or more |

When a source gives a range, the lowest ticket price decides the tier. The tiers and the guessing rules live in a new `data/schema/costs.json`, in the same style as `sizes.json`, so they can be tuned without code.

### Stored data

- A new optional event field `cost` with the values `free`, `$`, `$$` and `$$$`. Leaving it out means unknown.
- Only the tier is stored, never the amount. This keeps the existing rule in `docs/schema.md` ("no ticket prices", because event data belongs to the publishers) in spirit. The doc is updated to say tiers are stored and amounts are not.
- Descriptions still have dollar amounts removed, as now.

### How the tier is decided (first that applies wins)

1. **The source's own price data:**
   - Ticketmaster `priceRanges` (minimum).
   - The Events Calendar (tribe) `cost` text, which looks like "$32.75", "$10 - $20", "Free" or empty.
   - The `cost` field in scrape mode calendarapp.
   - SeatGeek lowest price.
   - Eventbrite free flag or price, if the event page has one.
   - A cost text of "free" or "$0" means free.
   - "Donation", "varies", or text with no number gives no tier from this step.
2. **The `free-admission` tag (my call):** `data/schema/tags.json` already tags free events from their text and source labels ("free admission", "free event", "free to attend", "no cover" and so on). An event with that tag gets cost `free`. There's no second phrase list, so the tag and the tier can't disagree. A dollar amount in the description (read before it's stripped) also sets the tier, when step 1 gave none.
3. **Rough rules from `costs.json`**, by source, venue, category or tag. Starting guesses (my call, tunable):
   - Library and city government sources: free. Chamber calendars get no free rule, because they also list paid banquets and classes.
   - College athletics: $.
   - Concerts and shows at XL venues (ExtraMile Arena, Ford Idaho Center, Albertsons Stadium): $$.
   - Idaho Steelheads: $$.
   - Everything else gets no rule at first.
4. **Otherwise:** no tier.

**Merging duplicates:** when the same event comes from several sources, a tier from step 1 or 2 beats a rule guess from step 3. Among real price data, the higher-priority source wins, the same as other fields.

**Existing events:** the rules in steps 2 and 3 can be applied to stored events by `-CleanupOnly` without network requests. Step 1 needs a normal ingest, so tiers from real price data fill in on the next nightly run.

## 4. Website

### Free shows nothing, on purpose

The owner decided that free and unknown look the same: nothing in the Cost column. So "Free" is never shown as a label. A free tier still matters for which tier wins in a merge and for the $ filters (a free event never shows up under $). Because of that, the free rules don't need much tuning; most of the effort belongs in the $, $$ and $$$ tiers.

### Desktop grid

- A new **Cost** column after Size.
- It shows `$`, `$$` or `$$$` in a small badge styled like the Size badge, with a tooltip ("Under $25", "$25 to $99", "$100 or more").
- Free and unknown both show nothing.
- The column is not sortable.

### Filter

- A new **Cost** select next to Venue Size, with these options: Any cost, Free or unknown, $ (under $25), $$ ($25 to $99), $$$ ($100 or more).
- "Free or unknown" shows events with tier free or no tier. Each $ option shows only that tier.
- It is kept in the URL like the other filters (suggested `cost=free|1|2|3`) and cleared by Reset.

### Broken links

- When an event is marked `linkBroken`, its title is plain text, not a link.
- Hovering over it shows "Information not available".
- The slim browser data in `home.html` carries the flag. The URL can be left out for those events.

### Phone card: 3 lines

- **Line 1:** date, time, and on the right the size badge with the cost badge next to it.
- **Line 2:** title (unchanged).
- **Line 3:** "City | Venue", for example "Nampa | Ford Idaho Center", with the category on the right. It stays on one line and ends in an ellipsis if too long.
  - When the city is missing or "Other", the line shows only the venue.
  - The separator is a vertical bar with a space on each side, the same look as the header's separators.
- The separate city line (line 4) goes away on phones. The desktop City column is unchanged.

## Testing and verification

- Pester tests with saved fixtures for both new sources, cost parsing (each source format and the text rules), tier rules, and link classification (mock `Invoke-WebRequest`, including the 403, timeout-twice and alternate-source cases).
- `Test-Schema.ps1` and `Test-Sources.ps1` pass with the new fields and entries.
- A local ingest of the two new sources with `-NoWrite`, and a local ingest with the link check on a small budget.
- Build the site locally with Hugo and look at it at desktop and phone widths: the Cost column, the filter, a broken-link title, and the 3-line card.

## Docs to update

`docs/sources.md` (two sources), `docs/schema.md` (cost, linkBroken, links.json, the price rule), `docs/development.md` (link check, `-NoLinkCheck`, where the log is).

## Left to the builder

- Adapter internals and naming, iCal versus microdata for the chamber, and page limits.
- The exact `excludeTitlePattern`, free-text phrases and starting rules, as long as they stay conservative.
- The structure of `links.json` and the exact link-check budget.
- Whether the link check runs hosts in parallel to fit the budget.
- Badge styling, within the existing look.
