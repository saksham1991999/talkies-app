---
version: "alpha"
name: Talkies
description: "Movie ticket diary for India. Every viewing becomes a ticket stub. Velvet, brass, ink. House lights down."
colors:
  primary: "#E8A41C"
  on-primary: "#241300"
  ground-dark: "#150C0E"
  surface-dark: "#241416"
  ink-dark: "#F4E9DF"
  ink-soft-dark: "#C9AC9C"
  ink-faint-dark: "#9A7F73"
  line-dark: "rgba(241, 229, 221, 0.2)"
  ground-light: "#F1EBDD"
  surface-light: "#F8F4EA"
  ink-light: "#2A1316"
  ink-soft-light: "#6B5450"
  line-light: "rgba(42, 19, 22, 0.17)"
  tonight: "#E8A41C"
  on-tonight: "#241300"
  tonight-light: "#7A5403"
  stamp: "#B0342B"
  velvet: "#3A1519"
  velvet-dark: "#2E1316"
  on-velvet: "#E9D8CF"
  on-velvet-light: "#EFDFD6"
  paper-cinema: "#F2CBC1"
  paper-ott: "#F0DC9C"
  paper-home: "#CDE0C3"
  paper-tv: "#C7D9E8"
  paper-other: "#F0EBDD"
  paper-ink: "#2A1316"
  paper-soft: "#6B5450"
  btn-dark: "#F4E9DF"
  on-btn-dark: "#241310"
  btn-light: "#2A1316"
  on-btn-light: "#F6F1E4"
  sindoor: "#B0342B"
  marigold: "#C77F12"
  peacock: "#1C6566"
  mehendi: "#5C7429"
  neel: "#2F4A86"
  jamun: "#5E2D50"
  gulabi: "#BD3F68"
  kesar: "#D0662A"
  paan: "#3A7A4B"
  chai: "#7A4C2B"
  kajal: "#2B2424"
typography:
  hero:
    fontFamily: "SF Pro"
    fontSize: 44px
    fontWeight: 800
    lineHeight: 1.02
    letterSpacing: -0.015em
  screen-title:
    fontFamily: "SF Pro"
    fontSize: 32px
    fontWeight: 800
    lineHeight: 1.05
    letterSpacing: -0.01em
  stub-title:
    fontFamily: "SF Pro"
    fontSize: 26px
    fontWeight: 800
    lineHeight: 1.05
    letterSpacing: -0.01em
  body:
    fontFamily: "SF Pro"
    fontSize: 17px
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: 0em
  secondary:
    fontFamily: "SF Pro"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0em
  meta:
    fontFamily: "SF Pro"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: 0em
  kicker:
    fontFamily: "SF Pro"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: 0.12em
  stamp-word:
    fontFamily: "Tanker"
    fontSize: 15px
    fontWeight: 400
    lineHeight: 1.0
    letterSpacing: 0.06em
  wordmark:
    fontFamily: "Tanker"
    fontSize: 26px
    fontWeight: 400
    lineHeight: 1.0
    letterSpacing: 0.02em
rounded:
  stub: 6px
  card: 16px
  pill: 22px
  chip: 4px
  ticket: 5px
  tab: 31px
  sheet: 18px
  input: 10px
  poster: 4px
spacing:
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 20px
  section: 24px
  hero-gap: 32px
  spread: 40px
  rest: 64px
components:
  screen-dark:
    backgroundColor: "{colors.ground-dark}"
    textColor: "{colors.ink-dark}"
  screen-light:
    backgroundColor: "{colors.ground-light}"
    textColor: "{colors.ink-light}"
  button-primary-dark:
    backgroundColor: "{colors.btn-dark}"
    textColor: "{colors.on-btn-dark}"
    rounded: "{rounded.pill}"
    padding: 16px
    typography: "{typography.secondary}"
  button-primary-light:
    backgroundColor: "{colors.btn-light}"
    textColor: "{colors.on-btn-light}"
    rounded: "{rounded.pill}"
    padding: 16px
    typography: "{typography.secondary}"
  ticket-paper-cinema:
    backgroundColor: "{colors.paper-cinema}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.stub}"
    padding: 16px
  stamp-watched:
    backgroundColor: "{colors.paper-cinema}"
    textColor: "{colors.stamp}"
    typography: "{typography.stamp-word}"
    size: 84px
  tab-bar:
    backgroundColor: "{colors.velvet-dark}"
    textColor: "{colors.on-velvet}"
    rounded: "{rounded.tab}"
    height: 64px
  tab-bar-light:
    backgroundColor: "{colors.velvet}"
    textColor: "{colors.on-velvet-light}"
    rounded: "{rounded.tab}"
    height: 64px
  tab-active-ticket:
    backgroundColor: "{colors.paper-cinema}"
    textColor: "{colors.paper-ink}"
    rounded: "{rounded.ticket}"
    height: 50px
  vote-pill-tonight:
    backgroundColor: "{colors.tonight}"
    textColor: "{colors.on-tonight}"
    rounded: "{rounded.pill}"
    padding: 16px
    typography: "{typography.secondary}"
  input-field-dark:
    backgroundColor: "{colors.surface-dark}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.input}"
    padding: 14px
  input-field-light:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.input}"
    padding: 14px
---

## Overview

Talkies is a movie ticket diary for Indian filmgoers. Every viewing becomes a ticket stub. Feel: velvet, brass, ink. The emotional core is the hall at 9 pm: tungsten practicals, maroon velvet, amber marquee glow, projector beam, dust, 35mm grain.

Dark mode ("House lights down") leads. Light mode ("Matinee") is the same hue family, material-led. Dual themes share one file via `-dark` / `-light` token suffixes. Tokens without a suffix (`tonight`, `stamp`, `paper-*`, accent inks) share one pigment in both modes; dark mode dims paper 12% toward ground, and surfaces and chrome use the `-dark` variants.

Scope: Flutter app only (`lib/ui/`, `assets/fonts/`, `assets/paper/`). The landing site (`docs/`) and store assets are out of scope.

## Colors

Dark ground `#150C0E`, raised velvet surface `#241416`. Ink `#F4E9DF`, soft `#C9AC9C`, faint `#9A7F73`, rule `rgba(241,229,221,.20)`. Light ground `#F1EBDD`, surface `#F8F4EA`, ink `#2A1316`, soft `#6B5450`, rule `rgba(42,19,22,.17)`.

- **Tonight (`tonight` #E8A41C, `on-tonight` #241300):** marquee amber means exactly one thing: tonight is on (live vote, poll leader, selected tab). Light-mode text variant `tonight-light` #7A5403 (passes AA on light ground). Fill is the same pigment both modes; dark text always sits on it.
- **Stamp (`stamp` #B0342B, same pigment as `sindoor`):** domain semantic for serials and WATCHED / FDFS ink, both modes. Errors use a separate red; stamp red never means error.
- **Velvet (`velvet` #3A1519, `velvet-dark` #2E1316, `on-velvet` #E9D8CF):** architecture only (tab chrome, sheets, snackbars). Never a button fill.
- **Paper by venue:** cinema pink `#F2CBC1`, OTT gold `#F0DC9C`, home green `#CDE0C3`, TV blue `#C7D9E8`, other `#F0EBDD`. Ink on paper is always `paper-ink` / `paper-soft`. Dark mode dims each paper 12% toward ground (see `Palette.paper()` in `lib/ui/theme.dart`).
- **Buttons:** ink fill in Matinee (`btn-light`), cream fill when house lights are down (`btn-dark`). Never amber, never maroon.
- **11 accent inks** (`sindoor` through `kajal`): user setting that recolors `accent`. `kajal` lifts 75% toward white in dark mode; others lift 12%. Source: `accents` in `lib/ui/theme.dart`.

## Typography

Display is Tanker (stamps, wordmark, figures) with Teko fallback for Devanagari. UI titles are SF Pro Expanded 800 Tight. Body is SF Pro. Numerals are tabular always.

- Hero 44 / screen title 32 / stub title 26 / body 17 / secondary 15 / meta 13 / kicker + tab labels 11. Weights stay two steps apart minimum.
- Stamps: Tanker, uppercase, rotated -11deg (-0.2 rad), double ring (2.6px + 1.1px), seeded wear specks. Stamp never overlaps live text.
- Kickers and tab labels are uppercase with wide tracking (kicker token 0.12em; `TALKIES 2026` header uses 2.4 spacing at 15px).
- 44 locales, the reach of the App Store's 50 metadata languages (English covers US, UK, Australia and Canada; Spanish covers ES and MX; Portuguese and Chinese split by region). The picker in Settings offers a language only once its ARB is translated, so a seeded file never appears as a broken translation.
- The printed words `WATCHED` and `FDFS` stay Latin in every locale: Tanker carries no other script, and a stamp that paints empty boxes is worse than an English stamp. Everything around them is translated.
- Right-to-left locales (Arabic, Hebrew, Urdu) flip the layout through `EdgeInsetsDirectional`, `TextAlign.start/end`, `AlignmentDirectional` and mirrored arrow icons. Ticket notches, perforation and stamps are symmetric and do not flip.
- Indian date formats everywhere; the intl locale comes from `intlLocaleOf()` in `lib/ui/format.dart`, with `zh_Hans` mapped to `zh_CN` and `zh_Hant` to `zh_TW`. Condensed Latin never ships: it clashes with the Devanagari fallback.

## Layout

Margin 20. Spacing scale 4/8/12/16/20/24/32/40/64. Groups 8-12 inside, 24-32 between sections, one 48+ rest per screen at the hero.

- 5 tabs: Home, Stubs, Films, Stats, Together (`lib/ui/shell.dart`). Search lives in the Films header, never its own tab. Record lives in context (header button + full-width dark button on empty states).
- Home order: Tonight hero (photo in dark, NightTicket in light) - counts - FDFS strip - latest stubs (4) - crew strip - For You / new / because-you-liked / coming-soon poster rails.
- Bottom nav (`TicketNav`): 64h velvet bar, dotted dividers, sliding paper ticket (notched, `TicketBorder` radius 5 notch 5 notchY 25) under the active tab. InkResponse radius 40, Semantics selected state.
- Screens scroll with 96px bottom padding so content clears the floating chrome. SafeArea bottom false; chrome floats above the indicator.
- Calendar cells share one tile surface; selected keeps 2.5px amber stroke, planned keeps dashed ring. Grid is fluid, verified at 375px.

## Elevation & Depth

Paper casts one tight shadow from above (offset 0/1.5, blur 1.4, `#402A1316`). Stubs add a 12/16 drop in mockups for the hero moment only.

- Grain: `assets/paper/grain.png`, repeat, opacity 0.55, scale 2, clipped inside the ticket shape under content (`TicketPaper` in `lib/ui/widgets.dart`).
- Dark hero: full-bleed hall photo with bottom-weighted scrim. Never set text over the bright screen area. Light hero: perforated stubs, deckled foil, grain multiply, mis-struck double stamp (ghost offset 3/2 at 30%).
- Sheet: top radius 18, surface fill, transparent tint. Snackbar: velvet fill, on-velvet text, OTT-gold action. Date picker header is velvet.
- Signature motion (record save, under 450ms, interruptible, reduced-motion 150ms cross-fade, haptics kept): stub lies bare, WATCHED drops 120px with stretch in a 180ms spring, impact spreads ink 2px + compresses stub 1px + heavy haptic + paper thock (sound off default), settles at -11deg with ghost. Secondary: tear-to-delete with Undo kept as-is.

## Shapes

Ticket bites are semicircles cut where perforation meets the edge (`TicketBorder`: radius, notch, `notchY` for left/right bites, `notchFromRight` for top/bottom bites).

- Stub rows 6 (full-stub detail and profile 10, swipe 8, tab ticket 5) / cards and home-night containers 16 (settings sheets 12-15) / pill 22 / word chips and chat bubbles 4 / glass tab 31 (concentric: inner = outer minus padding; the shipped bar is full-bleed velvet, the radius covers floating glass) / sheet-top 18 / input 10 / poster 4.
- Perforation: 1.6px round dashes every 7px in `paperInk` at 32% (`_PerforationPainter`). Foil divider on stubs: 1.5px dashed at 40%.
- Posters: 2:3 ratio, radius 4, fade 160ms in/out over a `TitleCard` placeholder. Offline or missing poster shows a typographic title card (Tanker on one of 7 deep inks).
- Icons (`Tk` set, `lib/ui/icons.dart`): one 24-grid set, 1.9 round stroke, closed shapes carry the ticket notch. 11px tab labels floor.

## Components

Tokens above are normative. `ticket-paper-cinema` stands for all venue papers: swap `backgroundColor` to `{colors.paper-ott}`, `{colors.paper-home}`, `{colors.paper-tv}` for OTT/home/TV. `stamp-watched` sits on paper; the red ring is graphic + word, sized 84. `vote-pill-tonight` is the only amber fill. `tab-active-ticket` slides 280ms easeOutCubic (zero when reduced motion).

- `SectionTitle` (20px ink, 11px kicker action in accent), `StubRow` (serial in stamp red, FDFS flag, ×N counterfoil), `EmptyNote` (dashed stub outline over 16% hall photo in dark), `Poster`/`TitleCard`, `NightTicket`, `FdfsStrip`, `Counts` (tabular 34-46 figures), rails (80x120 thumbs, 11px captions).
- Inputs: filled surface, 10px radius, line border, 1.4px ink focus, 14/12 padding, soft hint. Switches: on-accent thumb on accent track when selected. Chips: 10px. Deck words: uppercase 15px 0.8 tracking on paper.
- Share images: 12 `shareBackgrounds` + paper options; profile/share figures use 40-46 Tanker numerals.

## Do's and Don'ts

- Do use amber only for tonight/live/vote/selected tab. Don't use it for primary buttons, links, or decoration.
- Do keep maroon as architecture (tab chrome, sheets, snackbars). Don't fill buttons with amber or maroon.
- Do print stubs on venue paper with `paper-ink` text and grain under content. Don't put body text in stamp red; stamps are graphics and words, keep them legible and off live text.
- Do rotate stamps -11deg with the double ring and ghost. Don't center a FAB over the tab bar; don't ship a greeting header, purple gradient, emoji icons, or a dashboard stat-count row.
- Do keep the ticket the torn object: notch bites, perforation, counterfoil, grain. Don't set dark-hero text over the bright screen area.
- Don't add a search tab or a search-field radius: search lives in the Films header. Don't put CSV rows on the stub: export lives in Settings.
- Do run `npx @google/design.md lint DESIGN.md` before committing token changes. Don't invent new accent roles: the 11 inks remap `accent`, they never add a second tonight.
