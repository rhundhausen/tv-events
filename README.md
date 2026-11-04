# tv-events

tv-events is an automated reader of public event calendars in Idaho's Treasure Valley (Boise, Meridian, Nampa, Eagle, Caldwell, Garden City, Kuna, Star and nearby). It collects upcoming events into one non-commercial calendar. The public site is not live yet.

This page is for site owners who see the tv-events bot in their logs.

## Identifying the bot

Requests come with this User-Agent:

    tv-events/1.0 (+https://github.com/rhundhausen/tv-events)

## How it behaves

- Runs once a day, overnight in Boise (10:00 UTC).
- Reads only public sources: calendar feeds (ICS), WordPress event APIs, the City of Boise events API, official APIs such as Ticketmaster's, and a few public calendar pages.
- Calendar pages are checked against robots.txt on every run, including Crawl-delay, and a disallowed page is never requested.
- Feeds and APIs are checked against the site's robots.txt and terms when they are added as a source.
- Waits at least 1 second between paged requests.
- Never logs in, never bypasses paywalls or bot protection, and never disguises itself as a browser.

## What it keeps

For each event: title, date and time, venue, city, category, and a link back to the original listing. Descriptions are trimmed to a short summary.

It does not keep images, full descriptions, ticket prices, or personal information. Every listing links back to your page, so readers end up on your site.

## Opting out

The surest way is to **open an issue** in this repository naming the site you'd like removed. Your site will be taken off the source list and its events removed within a few days.

You can also block the bot in robots.txt:

    User-agent: tv-events
    Disallow: /

This stops page reading on the next run. If your site is read through a calendar feed or API, please open an issue as well, so that source is removed too.

## Contact

Questions, corrections, or concerns: open an issue in this repository.

## For developers

How the project is built, tested, and run: [docs/development.md](docs/development.md).
