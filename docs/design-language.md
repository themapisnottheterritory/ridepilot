# RidePilot design language

How GCRPC's RidePilot should look and feel, so every new screen, printout and
board is built from the same choices. Set down 2026-09-30 after the driver
manifest, the dispatch TV and the trouble board; Philz asked for it to be the
foundation, not a one-off. "Practical, but also elegant."

## Who it's for

Dispatchers with a phone in one hand, CSRs booking while a rider talks, drivers
reading a clipboard in a moving bus, a manager glancing at a TV. Every choice
below serves someone reading fast under mild stress. Pretty is in service of
that, never instead of it.

## Colour

GCRPC's brand, from the brand book and the report masthead:

| Role | Value | Use |
|---|---|---|
| Navy | `#12264F` | headings, table heads, primary badges, the brand mark |
| Navy (app chrome) | `#1f3864` | the web app's header, buttons, panel heads (older, keep for the app) |
| Gold | `#CC9900` | the one accent: rules under mastheads, DRAFT bands, "New" and will-call marks |
| Ink | `#131313` | body text |
| Muted | `#5f6b7a` | labels, secondary lines, footers |
| Line | `#cfd6e4` | hairlines, table rules |
| Soft | `#f4f6fa` | zebra rows, quiet panels |
| Good / Warn / Crit | `#0ca30c` / `#fab219` / `#d03b3b` | status only, never decoration |

Dark surfaces (the TV, the trouble board's hero) come from the call-center wall
on the PBX: `#07090d` background, `#0e1219`/`#121823` panels, the same status
colours. One accent per surface: gold on paper and the app, blue (`#3987e5`)
on the dark boards.

## Type

Open Sans for text; Copperplate Gothic Bold only for the organisation name in
mastheads and the app's page titles (it's the brand's serif; don't spread it).
System UI on the dark boards.

Sizes climb a golden-ratio ladder, φ = 1.618, so nothing is "a bit bigger",
it's the next rung:

- Print (points): 9 notes and small labels · 11 names and body · 14.5 run and
  section names · 23.5 the date, the one thing read first.
- Screen (px): 11 badges · 13 body · 14 forms · 18 section heads · 28 hero
  titles · 38 the one big number on a card.
- TV (viewport height): 1.8vh labels · 2.2–2.5vh body · 3.4vh the clock ·
  5vh strip figures · 17–22vh the one number the room reads across the room.

Bold is for the thing looked up first (the rider's name, the time), never for
emphasis mid-sentence. Tabular numerals for anything in a column.

## Proportion and space

- Split a width by φ where two things share it: rider 38 / address 62 on the
  manifest, the TV's hero 1 : 1.6 to the tiles. Three equal columns for
  peers (the three days).
- Padding pairs near 1 : 1.6 (5 × 8, 10 × 16, 14 × 22). Card radius 10px on
  screen, 2vh on the TV; badges 3–4px; pills 999px.
- One row per thing wherever a list is scanned: a stop, a trip, a note.
  Two lines in a cell are fine; a paragraph is not.
- Whitespace comes from removing, not adding: the manifest lost the funding
  source and a broken logo and gained phone, mobility and fare, and still
  went from 7 pages to 2.

## Elements

- **Badges** say state in one word (PU/DO, Will call, Wheelchair, New, DRAFT,
  Live). Filled navy for the primary state, outlined for the secondary, gold
  for "pay attention", status colours only for status.
- **Cards** carry one idea each, with a 4px coloured top edge on boards where
  colour is the category.
- **Tables** have a navy head that repeats on every page, hairline rules,
  soft zebra, nothing split across pages.
- **Write-in blanks** on paper are underlines, one row, never boxes.
- **Empty states** say what would fill them ("Runs show up here when a driver
  starts one on the tablet"), in a calm green, not a warning.
- **Brand mark**: the seal, trimmed to its edge, at the golden share of its
  container (62 of 100). Never stretched; never with the padded canvas.

## Voice

Plain words a dispatcher would use: "pick up", "bus", "rider", "run"; never
"itinerary", "vehicle type", "provider" on anything staff or drivers read.
Notes and footers are one sentence. Warnings say what to do next.
People are never scored: boards count trips and screens, not people.

## When building something new

1. Who reads it, and what do they look up first? Make that the biggest thing.
2. Cut what they don't need before styling what they do.
3. Pick the rung on the ladder; pick one accent; check it on a phone or the
   real paper size.
4. Name it for what it is, not the code's word for it.
