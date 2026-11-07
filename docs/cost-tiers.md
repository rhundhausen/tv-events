# Cost tiers

Two cost values are involved, and only one is stored:

- `priceMin`: number or null. Cheapest adult ticket, face value, before fees.
  Source scripts work it out and pass it to `New-TvEvent`. It is never
  stored: WeekendBoise keeps no ticket prices (see the README).
- `costTier`: one of `free`, `$`, `$$`, `$$$`, or null (unknown). Stored on
  the event; left out when null.

`costTier` is derived from `priceMin` by one shared function, `Get-CostTier`
in `ingestion/scripts/lib/Cost.ps1`, at ingest time. Source scripts never set
`costTier` directly. Breakpoints live in one config block,
`$CostTierBreakpoints` at the top of that file, so they can be retuned without
touching source scripts. Refine copies them into `data/meta.json` for the
site's legend.

There are no guessed tiers: an event whose source gives no price, and whose
description names none, is unknown.

## Breakpoints

| Tier | Rule |
|------|------|
| free | priceMin is 0 |
| $ | 0 < priceMin < 15 |
| $$ | 15 <= priceMin < 40 |
| $$$ | priceMin >= 40 |
| null | priceMin is null (unknown) |

## Which price

- Cheapest adult ticket. Ignore kids, senior, student, and member pricing.
- Face value before service fees.
- Price ranges ("$10 to $60"): use the low end.
- Multiple ticket types with no clear adult price: use the lowest listed.

## Edge cases

- Suggested donation or pay-what-you-can: free.
- Free entry with paid parking, food, or activities: free.
- Multi-day or season pass with no single-day price: priceMin = pass price.
- "Tickets at the door" or "see website" with no amount: null.
- Sold out: keep the original price; cost is independent of availability.
- A price of 0 in a page's schema.org offers is a placeholder, not free:
  sites put it in by default (Bluebird lists a $39 show at 0). It counts as
  free only when the page also marks the event free (`isAccessibleForFree`),
  or on Eventbrite, whose offers are reliable.

## Display

- Table cell shows `Free`, `$`, `$$`, or `$$$`. Unknown renders blank.
- No hover on the cell: the price is not stored. The legend explains the tiers.
- Cost filter offers: Any cost, Free, $, $$, $$$. Unknown appears under Any only.
- Legend with the dollar ranges goes in the Cost column header tooltip.

## Backfill

The nightly ingest refetches every source and re-derives costTier for every
upcoming event, so breakpoint changes take effect on the next run with no
migration. Archived (past) events keep the tier they had, because no price is
stored to re-derive it from.

Events stored before this scheme (fields `cost` and `costGuess`, with tiers at
$25 and $100) are moved by refine (`Update-TvLegacyCost`): `free` and `$$$`
carry over because they mean the same under the new breakpoints; old `$`, `$$`,
and every guess are dropped, and the next ingest gives upcoming events their
tier again.

Each refine counts upcoming events per tier (`costTiers` in `out/refine.json`)
and the refine email shows the counts, so the effect of the breakpoints is
visible every night.
