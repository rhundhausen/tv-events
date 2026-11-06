# Emmett sources, link check, cost tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Gem County Chamber and Eventbrite Emmett sources, a polite nightly link check that unlinks dead event pages, a Free/$/$$/$$$ cost tier with a filter, a 3-line phone card, and site deploys on every data push.

**Architecture:** Cost comes in two stored fields. `cost` comes from real price data, set by adapters through `New-TvEvent -Cost` and merged like other fields. `costGuess` comes from `data/schema/costs.json` rules and is recomputed after every merge, so a guess never beats real data. The link check is a new `lib/Links.ps1`, run by `Invoke-Ingest.ps1` after the merge. Its state is in `data/links.json`, and it sets `linkBroken` on events. The site reads `cost || costGuess` and `linkBroken` from the slim JSON.

**Tech Stack:** PowerShell 7.4 + Pester 5, Hugo 0.162.1, vanilla JS/CSS, GitHub Actions, Cloudflare Workers Builds.

**Spec:** `docs/superpowers/specs/2026-11-05-emmett-links-cost-design.md`

## Global Constraints

- **Tiers:** free = $0; `$` = under $25; `$$` = $25 to $99; `$$$` = $100 or more. The lowest price in a range decides.
- **No amounts stored:** never store a price amount; descriptions keep dropping sentences with dollar amounts.
- **Free shows nothing:** free and unknown both render nothing. The filter option reads "Free or unknown".
- **Broken-link tooltip:** the hover text is exactly "Information not available".
- **Phone line 3:** "City | Venue" (space, vertical bar, space); only the venue when the city is empty or "Other".
- **Link checks never break on bot answers:** 401, 403 and 429 never mark a link broken. Timeouts, 5xx, DNS failures and refused connections need 2 nights in a row. 404 and 410 break on the first night.
- **Politeness:** every request uses `Get-TvUserAgent`, obeys robots.txt, and keeps at least 1 second (or the host's Crawl-delay) between requests to one host.
- **Writing style:** no en or em dashes anywhere.

## Review Focus

- **Ticketmaster answers scripts with 403:** those links must stay linked. Test: `Get-TvLinkVerdict` with 403 returns `blocked`, never `broken`.
- **Cost text oddities:** "Free - $20", "$0 - $15", "Donation", "$10 suggested". Test cases in `ConvertFrom-TvCostText`.
- **A carried event with an old guess merging with a fresh event that has real price data:** real wins. Test in Dedupe.
- **An event with no city, or city Other, on a phone:** line 3 is the venue alone. Covered in the JS (manual check at 390px).
- **First-night backlog bigger than the budget:** the run finishes inside the budget and unchecked links stay linked. Test: `Invoke-TvLinkCheck` with `-BudgetSeconds 0` checks nothing and marks nothing broken.

---

### Task 1: Cost tier core

**Files:**
- Create: `data/schema/costs.json`, `ingestion/scripts/lib/Cost.ps1`, `ingestion/tests/lib/Cost.Tests.ps1`
- Modify: `ingestion/schema/event.schema.json`, `ingestion/scripts/lib/Schema.ps1` (`New-TvEvent`), `ingestion/scripts/lib/Dedupe.ps1` (`Merge-TvEvents`), `ingestion/scripts/Invoke-Ingest.ps1`

**Interfaces (produces):**
- `Get-TvCostTier -Amount <double>`: returns `'free'|'$'|'$$'|'$$$'`.
- `ConvertFrom-TvCostText -Text <string>`: returns a tier or `$null`. It reads "Free", "$0", "$32.75", "$10 - $20", "Free - $20". The lowest number wins, and the word free with no number means free. "Donation", "varies" and empty text give `$null`.
- `Get-TvCostGuess -Event <object> -SourceNames <string[]>`: returns a tier or `$null`, from the `costs.json` rules (`sources`, `venues`, `tags`, `categories` maps; first match in that order).
- `Set-TvCostGuess -Events <object[]>`: sets or removes `costGuess` on each event. It is removed when `cost` is set.
- `New-TvEvent -Cost <string>`: an optional tier from the source. If it's empty, the event gets `free` when its tags include `free-admission`, else the tier of the lowest dollar amount in the raw description, else nothing.
- **Event schema:** optional `cost` and `costGuess`, both enum `["free","$","$$","$$$"]`.

- [ ] **Step 1: Write the tests** in `Cost.Tests.ps1`:
  - `Get-TvCostTier` maps 0, 24.99, 25, 99.99 and 100 to free, $, $$, $$ and $$$.
  - `ConvertFrom-TvCostText` maps "Free" to free, "$32.75" to $$, "$10 - $20" to $, "Free - $20" to free, and "Donation" and "" to null.
  - `New-TvEvent` with a description "Tickets are $45." gives cost `$$` and a description without that sentence. A title "Free Admission Day" gives `free`. `-Cost '$$$'` beats both.
  - `Set-TvCostGuess` gives a `nampa-public-library` event `costGuess` free. An event with `cost` set gets no `costGuess`.
  - In Dedupe tests, a higher-priority event without `cost` merged with a lower-priority one with `cost '$$'` keeps `$$`. A higher-priority event with `cost '$'` keeps `$`.
- [ ] **Step 2: Run** `Invoke-Pester ingestion/tests/lib/Cost.Tests.ps1`. Expected: FAIL (functions missing).
- [ ] **Step 3: Implement.** Starting `costs.json` rules (spec section 3):
  - **sources, free:** `boise-public-library`, `nampa-public-library`, `kuna-library`, `mountain-home-library`, `city-of-boise`, `city-of-kuna`, `city-of-star`.
  - **sources, $:** `boise-state-athletics`, `college-of-idaho-athletics`, `nnu-athletics`.
  - **sources, $$:** `idaho-steelheads`.
  - **venues, $$** (music and performing-arts only): `extramile-arena`, `extra-mile-arena`, `ford-idaho-center`, `ford-idaho-center-arena`, `ford-idaho-center-amphitheater`, `albertsons-stadium`.

  `Schema.ps1` dot-sources `Cost.ps1`. `Merge-TvEvents` copies `cost` onto the target when the target has none. `Invoke-Ingest.ps1` calls `Set-TvCostGuess` after the merge in both the normal and the `-CleanupOnly` paths, and over the archive months in cleanup.
- [ ] **Step 4: Run** the full suite: `Invoke-Pester ingestion/tests`. Expected: all pass.
- [ ] **Step 5: Commit** "Add cost tiers from price data, text, and rules".

### Task 2: Read prices in existing adapters

**Files:**
- Modify: `adapters/ticketmaster.ps1`, `adapters/tribe.ps1`, `adapters/scrape.ps1` (calendarapp `cost`, and jsonld `offers`), `adapters/seatgeek.ps1`
- Test: `tests/adapters/*.Tests.ps1`, with the existing fixtures (`tribe/mike-brown-group.json` has `$32.75` and `$13.10`)

**Interfaces (consumes):** `ConvertFrom-TvCostText`, `Get-TvCostTier`, `New-TvEvent -Cost` (Task 1).

**Where each adapter gets its price:**
- **Ticketmaster:** `priceRanges[].min`, the minimum across the ranges.
- **Tribe:** `cost` text.
- **Calendarapp:** `cost` text.
- **JSON-LD:** `offers.price`, or `offers.lowPrice`. `isAccessibleForFree` true means free.
- **SeatGeek:** `stats.lowest_price`. Update the "prices are ignored" note in `docs/sources.md`.

- [ ] **Step 1: Write the tests:**
  - The Mike Brown Group event priced `$32.75` gets cost `$$`, and the one with an empty cost has no `cost`.
  - The Ticketmaster fixture event with `priceRanges` gets its tier. If the fixture has no priceRanges, add one to a copy of the fixture.
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement** in each adapter.
- [ ] **Step 4: Run** the full suite. Expected: pass.
- [ ] **Step 5: Commit** "Read ticket price tiers from adapters".

### Task 3: Gem County Chamber (scrapeMode chambermaster)

**Files:**
- Modify: `adapters/scrape.ps1` (new `Read-ChamberMasterSource`), `ingestion/sources.json`, `ingestion/schema/sources.schema.json` (if scrapeMode is an enum), `docs/sources.md`
- Create: `tests/fixtures/scrape/chambermaster-calendar.html` and `chambermaster-event.ics` (saved from the live site, trimmed)
- Test: `tests/adapters/Scrape.Tests.ps1`

**What the reader does:**
- It reads the month calendar at `url` for this month and the next `maxPages - 1` months (default 3). Month 2 and later use `?month=YYYY-MM-01` (the builder confirms the query the site uses for its next-month link).
- It collects links matching `/events/details/<slug>-<id>` and drops the query string.
- For each event, it fetches `/events/addtocalendar/<slug>-<id>?format=ICal` and parses it with the existing ICS helpers in `lib/Ics.ps1`. It applies `excludeTitlePattern` and skips past events.
- Detail requests go through `Get-ScrapePage` (robots.txt and delay). The `-Response` order for tests is: calendar page(s), then each event's ICS.

**Source entry:**
- name `gem-county-chamber`, displayName "Gem County Chamber of Commerce", status running, adapter scrape, scrapeMode chambermaster.
- url `https://business.emmettidaho.com/events/calendar/`, robotsChecked 2026-11-05.
- category community-civic, inferCategory, city Emmett, venue "Gem County Chamber of Commerce", venueKey `gem-county-chamber`, priority 20.
- excludeTitlePattern `(?i)\bworship\b|\bmeeting\b|\bclosed\b`, maxPages 3.
- Mark the existing `emmettidaho.com` idea entry as covered by this source (notes).

- [ ] **Step 1: Save the fixtures and write the tests:** a known Emmett event is read with the right title, start, city Emmett, and a URL of the `/events/details/...` page. A "Worship Service" item is dropped.
- [ ] **Step 2: Run.** Expected: FAIL (unknown scrapeMode).
- [ ] **Step 3: Implement** the reader and add the source entry.
- [ ] **Step 4: Run** the full suite plus `pwsh ingestion/scripts/Test-Sources.ps1`, then a live check with `pwsh ingestion/scripts/Invoke-Ingest.ps1 -Source gem-county-chamber -NoWrite`. Expected: pass, and events reported.
- [ ] **Step 5: Commit** "Add Gem County Chamber calendar (ChamberMaster)".

### Task 4: Eventbrite search page adapter

**Files:**
- Create: `adapters/eventbrite-search.ps1`, `tests/fixtures/eventbrite-search/emmett.html` (saved live page)
- Modify: `ingestion/sources.json`, the sources schema (if the adapter is an enum), `docs/sources.md`
- Test: `tests/adapters/ApiAdapters.Tests.ps1` or a new `EventbriteSearch.Tests.ps1`

**What the adapter does:**
- It fetches `https://www.eventbrite.com/d/<placeSlug>/events/` (and `?page=N` while more pages exist, up to `maxPages`, default 3). It checks robots.txt like `scrape.ps1` does, using the helpers in `lib/Scrape.ps1`.
- It parses `window.__SERVER_DATA__` with `JsonDecoder`-style reading (find the start of the object, then decode it with `ConvertFrom-TvJson` on the balanced text) and reads `buckets[].events[]`. Events can repeat across buckets, so it dedupes by `id`.
- It skips `is_online_event`, `is_cancelled`, and addresses with a region other than ID.
- `start_date` and `start_time` are in `timezone`. If there's no time, the event is all-day.
- The venue comes from `primary_venue.name`, and the city from `Resolve-TvCity primary_venue.address.city`, falling back to the source city.
- **Price:** for each event, fetch its `url` and read the JSON-LD offers through `Get-TvJsonLdEvent`. On a failure, keep the event without a cost. This applies only when the check in Step 1 shows the `/e/` pages carry offers; otherwise skip the price fetch.

**Source entry:**
- name `eventbrite-emmett`, displayName "Eventbrite (Emmett area)", status running, adapter `eventbrite-search`, placeSlug `id--emmett`.
- url `https://www.eventbrite.com/d/id--emmett/events/`, robotsChecked 2026-11-05.
- category community-civic, inferCategory, city Other, venue "Various Treasure Valley locations", venueKey `various-treasure-valley`, priority 70.

- [ ] **Step 1: Save the fixture and check the price data:** save the listing page and one `/e/` page, and check whether the `/e/` page has offers. Write the tests: 16 events or fewer after filtering, "Birding the Park at Expo Idaho" starts `2026-11-08T08:30:00-07:00` in Garden City, no online events, and the source name is recorded.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the adapter and the source entry.
- [ ] **Step 4: Run** the suite, `Test-Sources.ps1`, and `Invoke-Ingest.ps1 -Source eventbrite-emmett -NoWrite`. Expected: pass.
- [ ] **Step 5: Commit** "Add Eventbrite search page adapter for Emmett".

### Task 5: Nightly link check

**Files:**
- Create: `ingestion/scripts/lib/Links.ps1`, `ingestion/tests/lib/Links.Tests.ps1`
- Modify: `ingestion/schema/event.schema.json` (`linkBroken` boolean), `ingestion/scripts/Invoke-Ingest.ps1` (`-NoLinkCheck`, `-LinkBudgetSeconds` default 900), `.github/workflows/ingest.yml` (job summary), `docs/development.md`, `docs/schema.md`

**Interfaces (produces):**
- `Get-TvLinkVerdict -Status <int> -ErrorKind <string>`: returns `ok`, `broken`, `blocked` or `transient`.
  - 2xx and 3xx: `ok`.
  - 404 and 410: `broken`.
  - 401, 403 and 429: `blocked`.
  - 5xx, `timeout`, `dns` and `refused`: `transient`.
- `Test-TvLink -Url <string>`: makes the request and returns `@{ Status; ErrorKind; Verdict }`. It sends a GET with `-MaximumRedirection 10`, `-TimeoutSec 20` and `-SkipHttpErrorCheck`, and maps exceptions to `dns`, `refused` or `timeout`.
- `Invoke-TvLinkCheck -Events <object[]> -State <hashtable> -Now <DateTimeOffset> -BudgetSeconds <int>`: returns `@{ State; Checked = [list]; Broken = [list] }` and sets `linkBroken` on events.
  - **State entries** are keyed by URL: `@{ verdict; checkedAt; brokenSince; failures }`.
  - **Due:** a URL with no entry, `ok` older than 7 days, `blocked` older than 7 days, or `broken` or `transient` older than 20 hours. Due links are checked soonest event first.
  - **Robots:** each host's robots.txt is fetched once per run. Disallowed paths are skipped.
  - **Spacing:** at least 1 second (or the Crawl-delay) between requests to one host.
  - **Broken after:** `broken` at once, or `transient` with `failures >= 2`.
  - **Fallback:** before an event is marked broken, each other distinct `sources[].url` is checked. The first `ok` one becomes `url`, and `sources` stay unchanged.
  - **Budget:** the check stops starting new requests once `BudgetSeconds` have passed.
- `Read-TvLinkState` / `Write-TvLinkState -Path data/links.json`: sorted keys, LF, 2-space indent, like `Write-TvEventFile`. Entries for URLs no longer in any event are pruned after 30 days.
- **Outputs:** `Invoke-Ingest.ps1` writes `out/links.json` (Checked and Broken lists) and adds `links` counts to `out/run.json`. When `$env:GITHUB_STEP_SUMMARY` is set, it appends a Markdown "Broken links" section, grouped by source, with the title, date, link and reason. New breaks are listed first.
- **When it runs:** with `-Source`, only events that source reported are checked. It does not run with `-CleanupOnly` or `-NoWrite`. Known broken results are still applied to every event.

- [ ] **Step 1: Write the tests,** mocking `Invoke-WebRequest`:
  - **Verdicts:** the table above.
  - **403 never breaks:** a 403 never sets `linkBroken`.
  - **404 breaks at once:** a 404 sets `linkBroken` and adds the event to the Broken list.
  - **Transient twice:** a timeout on night 1 leaves the link working. Then, with the state from night 1 and a `Now` 24 hours later, a second timeout sets `linkBroken`.
  - **Fallback:** a 404 on `url` with another source URL returning 200 switches `url` and does not set `linkBroken`.
  - **Recheck:** an `ok` entry checked 2 days ago isn't requested again.
  - **Budget:** `-BudgetSeconds 0` makes no requests and marks nothing broken.
  - **Robots:** a robots.txt Disallow covering the path means no request is sent to it.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `Links.ps1`, the `Invoke-Ingest.ps1` wiring, the schema field and the docs.
- [ ] **Step 4: Run** the full suite, then a live run with `pwsh ingestion/scripts/Invoke-Ingest.ps1 -Source idaho-history -LinkBudgetSeconds 60` (a small source) and read `out/links.json`. Afterwards, revert `data/` with `git checkout data` if the run wasn't meant to be committed.
- [ ] **Step 5: Commit** "Check event links nightly and unlink broken ones".

### Task 6: Website (cost column, filter, broken links, phone card)

**Files:**
- Modify: `website/layouts/home.html`, `website/assets/js/app.js`, `website/assets/css/site.css`

**Data, home.html:**
- Add these keys to the slim JSON: `"p"` holds `.cost` with `.costGuess` as the fallback, and `"x"` holds `.linkBroken`.
- Add a `<col class="w-cost">` and a `<th scope="col">Cost</th>` after Size.
- Add `<label class="field"><span class="label">Cost</span><select id="cost">` after Venue Size, with these options:
  - "" for "Any cost"
  - `free` for "Free or unknown"
  - `1` for "$ (under $25)"
  - `2` for "$$ ($25 to $99)"
  - `3` for "$$$ ($100 or more)"

**Behavior, app.js:**
- **State and URL:** add `state.cost`, kept in the URL as `cost`.
- **Filter:** `free` matches events whose `p` is empty or `free`; `1`, `2` and `3` match `$`, `$$` and `$$$`. Reset clears it.
- **Cost cell:** the `c-cost` cell shows a `.cost` badge for `$`, `$$` and `$$$`, with the titles "Under $25", "$25 to $99" and "$100 or more".
- **Broken links:** when `x` is true, the title is plain text and `title.title = 'Information not available'`.
- **Phone line 3:** add a hidden-on-desktop `c-place` span inside the venue cell, so the cell reads "City | Venue". Simpler alternative: render the venue cell text as `${city} | ${venue}` only for phone CSS via two spans, `.v-city` and `.v-name`, with `.v-city` hidden on desktop.
- **Empty row:** `colSpan` becomes 8.

**Layout, site.css:**
- **Desktop:** `.w-cost { width: 56px; }`. The `.cost` badge is styled like `.size`.
- **Phone, line 1:** the `.c-size` cell holds both badges on the right, so `.c-cost` sits in `grid-row: 1` and column 3 next to the size badge. Use a flex wrapper or put the cost badge inside the size cell for phones. The builder picks whichever keeps the desktop column intact.
- **Phone, line 3:** `.c-venue` is `grid-row: 3`, single line with an ellipsis. `.c-city` is `display: none` on phones. `.c-cat` is `grid-row: 3`.

- [ ] **Step 1:** `hugo build` in `website/`. Expected: success.
- [ ] **Step 2:** `hugo server` and check at 1280px and 390px wide:
  - the Cost column and its badges
  - the filter options and the `?cost=` URL
  - a `linkBroken` event (set one temporarily in a copy of the data, or use a test page) showing plain text and the tooltip
  - the phone card on 3 lines, with "Nampa | Ford Idaho Center"
- [ ] **Step 3: Commit** "Show cost tiers and broken links; 3-line phone card".

### Task 7: Deploy the site on every data push

**Files:**
- Modify: `ingestion/scripts/Publish-Data.ps1`, `docs/development.md`, `website/README.md`

**Why:** Cloudflare Workers Builds is connected (the check run "Workers Builds: weekendboise" succeeded on 74531cf) and deploys every push to main. But Cloudflare skips commits whose message has `[skip ci]`, so the nightly data commits never reach the site. The test workflow doesn't need `[skip ci]`, because pushes made with the workflow's `GITHUB_TOKEN` never start other workflows.

- [ ] **Step 1:** Change the commit message to `data: nightly ingest $date`, and update the comment and the docs (`docs/development.md` deploy section: push to main deploys; nightly data deploys too).
- [ ] **Step 2:** Run the full suite. Expected: pass.
- [ ] **Step 3: Commit** "Let nightly data commits deploy the site".
