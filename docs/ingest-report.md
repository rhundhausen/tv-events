# Ingest Report

A dry run on 2026-11-03 19:09 Boise time read all 35 running sources. 35 succeeded and 0 failed, giving 2,589 upcoming events and 475 past events. No source logged a warning or an error, and every event passed the schema. Nothing was loaded: the run used -NoWrite, so data/events.json still holds the 1,991 events from the last pipeline run.

sources.json now holds every source in one file: 111 entries, of which 35 run, 5 are configured and waiting, 22 are being investigated, 30 are ideas, and 19 are ruled out. 12 sources were added for this run, marked new below.

| Status | Sources | Meaning |
| --- | --- | --- |
| Running | 35 | Ingest reads it every night |
| Ready | 5 | Configured or adapter known, waiting on credentials or a decision |
| Feed found | 0 | A feed exists but is not configured |
| Investigating | 22 | Probed, nothing usable found yet |
| Idea | 30 | Not checked yet |
| Ruled out | 19 | Refused us, blocked by robots.txt, or not a calendar. Not probed again |
| Total | 111 | |

## Running sources

Fetched is what the source returned in this run. Upcoming counts its events within 180 days after merging, so an event reported by two sources counts for both. A source fetching more than its upcoming count is reporting past events, events past 180 days, or events another source already has.

| Source | Type | Status | Fetched | Upcoming | Warnings |
| --- | --- | --- | --- | --- | --- |
| City of Boise (new) | API (City of Boise) | OK | 75 | 59 | 0 |
| 9th St. Parallel at Knitting Factory (new) | API (Ticketmaster) | OK | 10 | 10 | 0 |
| Albertsons Stadium (new) | API (Ticketmaster) | OK | 2 | 0 | 0 |
| Danny Peterson Theatre (new) | API (Ticketmaster) | OK | 17 | 17 | 0 |
| Egyptian Theatre (new) | API (Ticketmaster) | OK | 8 | 6 | 0 |
| ExtraMile Arena | API (Ticketmaster) | OK | 27 | 22 | 0 |
| Ford Idaho Center Amphitheater (new) | API (Ticketmaster) | OK | 3 | 0 | 0 |
| Ford Idaho Center Arena | API (Ticketmaster) | OK | 17 | 7 | 0 |
| Idaho Central Arena (new) | API (Ticketmaster) | OK | 3 | 3 | 0 |
| Knitting Factory Boise | API (Ticketmaster) | OK | 40 | 40 | 0 |
| Morrison Center | API (Ticketmaster) | OK | 93 | 58 | 0 |
| Neurolux | API (Ticketmaster) | OK | 19 | 19 | 0 |
| Revolution Concert House (new) | API (Ticketmaster) | OK | 4 | 4 | 0 |
| Ticketmaster (metro-wide) | API (Ticketmaster) | OK | 151 | 119 | 0 |
| Bogus Basin | API (tribe) | OK | 5 | 4 | 0 |
| Boise Mom | API (tribe) | OK | 2,075 | 1,300 | 0 |
| Expo Idaho | API (tribe) | OK | 21 | 12 | 0 |
| Idaho Botanical Garden | API (tribe) | OK | 1 | 1 | 0 |
| Idaho Shakespeare Festival | API (tribe) | OK | 95 | 0 | 0 |
| Mike Brown Group | API (tribe) | OK | 119 | 115 | 0 |
| Western Idaho Fair | API (tribe) | OK | 0 | 0 | 0 |
| Boise Public Library (new) | ICS feed | OK | 500 | 199 | 0 |
| Boise State Arts and Entertainment | ICS feed | OK | 191 | 108 | 0 |
| Boise State Athletics | ICS feed | OK | 128 | 86 | 0 |
| College of Idaho Athletics | ICS feed | OK | 118 | 76 | 0 |
| Idaho Steelheads | ICS feed | OK | 34 | 34 | 0 |
| Nampa Public Library (new) | ICS feed | OK | 495 | 285 | 0 |
| Northwest Nazarene University Athletics | ICS feed | OK | 98 | 61 | 0 |
| Boise Arts and History (new) | Scrape (calendarapp) | OK | 19 | 19 | 0 |
| Boise Centre | Scrape (cards) | OK | 2 | 2 | 0 |
| JUMP Boise (new) | Scrape (cards) | OK | 46 | 45 | 0 |
| Idaho State Historical Society | Scrape (jsonld) | OK | 6 | 6 | 0 |
| Indian Creek Plaza | Scrape (jsonld) | OK | 5 | 5 | 0 |
| Visit Boise | Scrape (jsonld) | OK | 12 | 11 | 0 |
| Visual Arts Collective | Scrape (jsonld) | OK | 6 | 2 | 0 |

## Warnings and errors

None. All 35 sources succeeded, and no adapter skipped an event or logged a warning. Each run now writes out/run.json with every source's status, count, error, and warnings, so a failure shows up there and in the pipeline log.

Things that did not raise a warning but need attention:

- **Boise Public Library** returned 500 events, which looks like a cap: 288 were already past, and the rest reach only about 3.5 weeks ahead. A real load would also move those 288 past events, and 83 from Nampa Public Library, into the archive.
- **Library volume:** the two library feeds add about 480 upcoming events, mostly storytimes and recurring programs, which is why Learning and Business more than doubled, from 332 to 794. A title filter would trim them.
- **Idaho Shakespeare Festival** fetched 95 events, all in its 2027 season from May 21, more than 180 days out. **Western Idaho Fair** returned 0 events, as it did last time; its next fair is in August.
- **Ford Idaho Center Amphitheater** and **Albertsons Stadium** have no events within 180 days: their listings start in May and June 2027.
- **9th St. Parallel:** ticketmaster-metro still returns some of its shows under a second venue id. They merge with the venue source, so nothing is duplicated.
- **JUMP:** Boise Mom keys its 31 JUMP listings as jump-boise, so they could not merge with the JUMP Boise and City of Boise copies in this run (Family Boogie shows up twice, for example). A venue alias now fixes that from the next run.

<!-- pagebreak -->

## Results

| Category | Events |
| --- | --- |
| Learning and Business | 794 |
| Sports | 555 |
| Holiday and Seasonal | 331 |
| Community and Civic | 278 |
| Music | 195 |
| Performing Arts | 186 |
| Arts and Culture | 101 |
| Outdoors and Recreation | 67 |
| Markets and Shopping | 27 |
| Nightlife and Social | 26 |
| Festivals | 19 |
| Food and Drink | 10 |

Estimated size, a guess from the venue and event type: **S** (under 100) 1,268, **M** (100 to 999) 893, **L** (1,000 to 4,999) 328, **XL** (5,000 or more) 100. 133 upcoming events were reported by more than one source and merged.

## Added in this run

| Source | How it is read |
| --- | --- |
| Boise Public Library | LibCal ICS feed. Its own venue for every event, because the feed names rooms |
| Nampa Public Library | LibCal ICS feed, on its own host, separate from the ruled-out City of Nampa site |
| City of Boise | New cityofboise adapter for the JSON API behind cityofboise.org/events, including public meetings |
| Boise Arts and History | New calendarapp scrape mode for the event JSON embedded in the calendar page |
| JUMP Boise | Cards scrape with new date, title, and time patterns |
| 9th St. Parallel, Albertsons Stadium, Danny Peterson Theatre, Egyptian Theatre, Ford Idaho Center Amphitheater, Idaho Central Arena, Revolution Concert House | Ticketmaster venue sources. ticketmaster-metro skips their venue ids. Albertsons Stadium and Idaho Central Arena skip the games the team feeds cover |

## Configured but not running

| Source | Type | Why not |
| --- | --- | --- |
| Bandsintown | API (Bandsintown) | Needs an approved BANDSINTOWN_APP_ID. Keyed by artist, so it cannot list a venue's shows |
| boise-id.events | Scrape (jsonld) | Works, but it is a ticket-listing network (Live Entertainment Guide LLC) that repeats Ticketmaster and links to ticket pages. Left off on purpose; run it by hand with -Source boise-id-events |
| Eventbrite | API (Eventbrite) | Needs EVENTBRITE_TOKEN and a hand-kept list of organization or venue ids; location search was removed in 2019 |
| SeatGeek | API (SeatGeek) | Needs SEATGEEK_CLIENT_ID. Mostly resale, so primary sellers outrank it |
| Songkick | API (Songkick) | Needs SONGKICK_API_KEY and a metro area id. Access is unconfirmed |

<!-- pagebreak -->

## Not implemented yet

### Investigating

Probed, with no usable feed found yet. The notes say what was tried, so the next attempt can try something else.

| Source | Notes |
| --- | --- |
| Ada Community Library | Checked 2026-10-30 with the project User-Agent. Tribe endpoint responds, but with zero upcoming events. Past events not checked. ICS not tried |
| Ballet Idaho | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. ICS not tried |
| Block 22 Hotels | Site: block22llc.com. Hotel group page titled Boise Events Calendar. Static Webflow page with no event listings in the HTML (checked 2026-11-03); events may load from js/block22-hotels.js, not checked |
| Boise Art Museum | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. ICS not tried |
| Boise Contemporary Theater | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. ICS not tried |
| Boise Hawks | Checked 2026-10-30 with the project User-Agent. No tribe endpoint. ICS not tried |
| Boise Little Theater | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. Ticketmaster metro covers it |
| Boise Metro Chamber | Site: web.boisechamber.org. GrowthZone Atlas calendar, a JavaScript app; the HTML has no events (checked 2026-11-03). robots.txt allows it with a 10 second crawl delay. GrowthZone may offer an ICS or RSS export; none is linked from the page |
| Boise Music Festival | Checked 2026-10-30 with the project User-Agent. /wp-json/ returns an HTML page, not JSON. ICS not tried |
| Boise State Public Radio | Site: boisestatepublicradio.org. Community calendar is an evvnt widget; the HTML has no events (checked 2026-11-03). Same vendor as the Idaho Press calendar. evvnt has a publisher API that needs a key |
| Boise Weekly | Site: idahopress.com. The calendar now lives on idahopress.com (BLOX CMS). Events come from an evvnt widget (partner IDAHOPRESS) and are not in the HTML. The page links its own RSS (/search/?f=rss&t=article&c=boiseweekly/local-events), which robots.txt allows, but it returned HTTP 429 on 2026-11-03; retry once on another day. evvnt has a publisher API that needs a key |
| Boise With Kids | Site: boisewithkids.com. WordPress with the Simple Calendar plugin, which renders a Google Calendar on the server. The Google calendar id is not in the page, so its public ICS cannot be found; ask the site owner. Homepage showed 4 events on 2026-11-03. Family events; Boise Mom covers similar ground |
| Discovery Center of Idaho | Checked 2026-10-30 with the project User-Agent. No schema.org Event data on event pages, so scrape cannot read them reliably. Boise Mom lists many of their events |
| Downtown Boise Association | Site: downtownboise.org. Checked 2026-10-30 with the project User-Agent: no schema.org Event data on event pages. Rechecked /events/events-calendar on 2026-11-03: robots.txt allows it, but the calendar renders with JavaScript (ctycms platform) and the HTML has no events or feed links. Boise Mom lists many of their events |
| Hello Meridian | Site: hellomeridian.com. Squarespace community calendar that mixes many sources (Nampa library, Boise State football, local shops). robots.txt disallows the format=ical and format=json URLs. The list page has no schema.org data; event pages not checked. Mostly duplicates other sources, but useful for finding new ones |
| Idaho Conservation League | Checked 2026-10-30 with the project User-Agent. No tribe endpoint. ICS not tried |
| Idaho Humanities Council | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. ICS not tried |
| Stage Coach Theatre | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. ICS not tried |
| The Olympic | Tribe API works but reported zero events on 2026-11-02. robots.txt asks for 600 seconds between requests, so it needs a single request per run. Eventbrite may be its real calendar |
| This Is Boise | Site: thisisboise.com. WordPress blog. The annual event calendar is an article (one post a year) linking to organizers' pages, not a feed (checked 2026-11-03). Useful as a list of ideas. Also has a Facebook page; see Facebook pages |
| Totally Boise | Site: totallyboise.com. DNN site. Events load through a tb-event-viewer script, so the HTML has none (checked 2026-11-03). An aggregator, so mostly duplicates of venue sources |
| Treefort Music Fest | Checked 2026-10-30 with the project User-Agent. No tribe route and no schema.org Event data. Ticketmaster metro covers Treefort Music Hall |

### Ideas

Not checked yet. Most came from your notes; anything you dictated is kept as written in the notes.

| Idea | Notes |
| --- | --- |
| Air shows | Gowen Thunder (Idaho Air National Guard, Boise, not every year) and Warhawk Air Museum events in Nampa |
| Boise Bucket List | Site: boise-bucket-list.ck.page. Paid monthly events list sold through ConvertKit. Probably not a feed; read terms |
| Boise Depot | Dictated as 'the train depot'. City-owned; events may come through Boise Parks and Recreation |
| Boise Event Center (boiseeventcenter.com) | Site: boiseeventcenter.com. From a dictated link to a fall 2026 concert guide. Unknown site; read terms before probing |
| Boise Parks and Recreation | Dictated as 'Boise city park schedule' plus Ann Morrison Park, Julia Davis Park, and Camel's Back Park (dictated 'Camelback'). Parks don't publish their own calendars; events there come from the department or from organizers |
| Boise Towne Square | Dictated as 'the town Square mall' |
| Caldwell Night Rodeo | Dictated as 'rodeos in the area'. August |
| Chambers of commerce | Boise Metro Chamber has its own entry. Meridian Chamber, Nampa Chamber, and Caldwell Chamber each have their own site. Many chambers use GrowthZone (ChamberMaster) |
| Danielle Hahn Real Estate | Silvercreek Realty agent who posts a 'Treasure Valley this week + weekend' graphic (seen for Oct 8 to 10, 2026). An image, not a feed; useful as a cross-check |
| Facebook pages | Facebook's Events API for pages was restricted in 2018, and the site requires login, so scraping it is out under the project rules. Needs a different route, like an organizer's own site. Suggested 2026-11-03: the This Is Boise page (facebook.com/ThisIsBoise), not probed; This Is Boise has its own entry |
| Firebird Raceway | Drag racing season schedule |
| Front Street Fights | Boise MMA promotion. Also covers the 'boxing matches' and 'MMA' notes; other fight promoters unknown |
| Gun shows | Shows at Expo Idaho already come from expo-idaho. Other promoters and venues unknown |
| Hampton Inn and Suites Boise Downtown | Public events at the hotel. Boise for now; exact location to confirm |
| Home2 Suites by Hilton | Dictated as 'home to'. Public events at the hotel. Boise for now; exact location to confirm |
| Hotel 43 | Public events at the hotel |
| Hyde Park | A North End neighborhood, not a venue. Hyde Park Street Fair is run by the North End Neighborhood Association |
| Idaho Department of Fish and Game | Dictated as 'fishing game schedule'. Hunter education classes, clinics, and public meetings |
| Idaho State Capitol | Dictated as 'protests at the capitol'. Public events on the Capitol grounds come from the state (permits) or from organizers, not from one calendar |
| Meetup.com | Local in-person events only. robots.txt allows /find/us--id--boise/ (checked 2026-11-03); the page was not fetched. Meetup's API is restricted to paid tiers; read terms before anything else |
| Meridian Speedway | Oval track season schedule |
| Nampa Civic Center | City of Nampa is ruled out (HTTP 403). Check whether the civic center site is a separate host before probing |
| Public libraries outside Boise | Meridian Library District, Caldwell Public Library, Eagle Public Library. Boise Public Library, Ada Community Library, and Nampa Public Library have their own entries. City of Nampa and City of Eagle are ruled out; check whether a library site is a separate host before probing. Many libraries use LibCal, which publishes ICS |
| Radio station calendars | Boise State Public Radio has its own entry. Commercial stations list promoted shows |
| Rooted in Boise | Site: rootedinboise.com. Newsletter and blog with a monthly events post, also at https://rootedinboise.substack.com (for example /p/november-in-boise-2026). Read terms before probing |
| Snake River Stampede | Dictated as 'rodeos in the area'. July, at the Ford Idaho Center, so ford-idaho-center-arena may already cover it |
| The Linen Building | Downtown event venue on Grove St. Mostly private rentals; look for its public calendar |
| The Riverside Hotel | Public events, including live music on the Sandbar patio in summer |
| The Timbers at Harris Ranch | Apartment community that posts a 'What's happening in Boise' weekend graphic (seen for Oct 16 to 18, 2026). An image, not a feed; useful as a cross-check |
| The Village at Meridian | Dictated as 'the village mall'. Concerts at the fountain, seasonal events |

<!-- pagebreak -->

## Ruled out

Not probed again. Each needs the publisher's permission or a different feed.

| Source | Reason |
| --- | --- |
| AXS | HTTP 403 on 2026-10-30. Refuses automated requests |
| Boise Philharmonic | HTTP 401 on 2026-10-30. The REST API requires login |
| BoiseDev | HTTP 403 with a Cloudflare challenge page on 2026-11-03, although robots.txt allows /calendar/ |
| Brown Paper Tickets | HTTP 503 on 2026-10-30. Refuses automated requests |
| City of Eagle | robots.txt disallows /common/modules/icalendar/ and asks for a 10 second crawl delay |
| City of Meridian | HTTP 403 with a Cloudflare challenge page on 2026-10-30 |
| City of Nampa | HTTP 403 on 2026-10-30. Refuses automated requests |
| Etix | HTTP 202 with an empty page on 2026-10-30, which looks like a bot queue |
| Idaho Statesman | robots.txt timed out twice on 2026-11-03 (30 seconds each). RFC 9309 says to treat an unreachable robots.txt as disallowing everything |
| KTVB | Not an events calendar. /community/ lists news stories, with an RSS feed of articles (feeds/syndication/rss/news/community), checked 2026-11-03 |
| Morton Theatre | It is in Athens, Georgia, not Idaho |
| Opera Idaho | HTTP 403 on 2026-10-30. Refuses automated requests |
| Showclix, TicketLeap, and Tix | These sell tickets for individual organizers, so there is no local list to read without knowing each organizer. Add an organizer as its own idea instead |
| StubHub | Partner API only, and resale duplicates primary listings |
| The Scout Guide Boise | HTTP 403 with a Cloudflare challenge page on 2026-11-03, although robots.txt allows /boise/events/ |
| Trailhead Boise | HTTP 403 on 2026-10-30. Refuses automated requests |
| Visit Idaho | HTTP 403 with a Cloudflare challenge page on 2026-10-30 |
| Yelp | robots.txt disallows /search (checked 2026-11-03) |
| Zoo Boise | HTTP 403 on 2026-10-30. Refuses automated requests |

## Known problems

- **Duplicates:** titles that differ too much do not merge, such as BSU Women's Basketball Game and Boise State University Women's Basketball vs UC Davis. Boise State Theatre Arts Presents A Christmas Carol has the same problem.
- **Showings:** same-day matinee and evening shows still merge into one event.
- **Size:** the venue rule is blunt, so every ExtraMile game is XL and student recitals at the Morrison Center are L.
- **Scrapers:** they fail when sites change, and a changed page may return no events without an error. Seven sources now scrape: Boise Centre, Idaho State Historical Society, Indian Creek Plaza, Visit Boise, Visual Arts Collective, JUMP Boise, and Boise Arts and History (embedded JSON).
- **User-Agent:** requests still name the old GitHub URL as the contact. It needs a public contact before this runs nightly against so many sites.

## Needed from you

- **Decide:** whether same-day showings stay separate, and whether to trim the library feeds before loading.
- **Contact:** a public URL or email for the User-Agent.
- **Credentials:** SeatGeek and Eventbrite are the next useful keys, as tv-events-secrets variables.
- **Review:** terms of use for the scraped sites before this goes public. None has been read yet.
- **Then:** commit and push. The nightly pipeline will run the 35 sources and load the data.
