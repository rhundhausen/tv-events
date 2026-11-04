# tv-events

tv-events is an automated reader of public event calendars in Idaho's Treasure Valley (Boise, Meridian, Nampa, Eagle, Caldwell, Garden City, Kuna, Star and nearby). It collects upcoming events into one non-commercial calendar. The public site is not live yet.

This page is for site owners who see the tv-events bot in their logs.

## Identifying the bot

Requests come with this User-Agent:

    tv-events/1.0 (+https://github.com/rhundhausen/tv-events)

## How it behaves

- Runs once a day, overnight in Boise (10:00 UTC).
- Reads only public pages and feeds: ICS calendars, WordPress event APIs, official APIs such as Ticketmaster's, and public calendar pages.
- Checks robots.txt before every request and follows its rules for the `tv-events` user agent, including Crawl-delay.
- Waits at least 1 second between paged requests.
- Never logs in, never bypasses paywalls or bot protection, and never disguises itself as a browser.

## What it keeps

For each event: title, date and time, venue, city, category, and a link back to the original listing. Descriptions are trimmed to a short summary.

It does not keep images, full descriptions, ticket prices, or personal information. Every listing links back to your page, so readers end up on your site.

## Opting out

Either of these works:

1. **robots.txt.** Add the following to your site's robots.txt and the next run will skip your site:

       User-agent: tv-events
       Disallow: /

2. **Ask.** Open an issue in this repository saying which site you'd like removed. Your site will be taken off the source list and its events removed within a few days.

## Contact

Questions, corrections, or concerns: open an issue in this repository.