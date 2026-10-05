# SEO log for the Talkies landing page

Cold-start note: GitHub Pages serves `main`/`docs` at
https://saksham1991999.github.io/talkies-app/.
Work happens on the `recommendations` branch. Nothing here is live until
`recommendations` merges to `main` and pushes.

## Changelog

- 2026-10-05: Landing-page SEO/AEO/GEO pass (this session).
  - `docs/index.html`: title now `Talkies: Movie Ticket Diary for India`;
    meta description rewritten to ~155 chars; added self-referencing
    canonical, `robots` (`index,follow,max-image-preview:large`),
    `lang="en-IN"`, full OG + Twitter tags with image dims/alt.
  - Added JSON-LD `@graph`: SoftwareApplication (no aggregateRating, none
    exist), Organization, WebSite, FAQPage (8 Q&As, answers mirror the
    visible FAQ copy).
  - Demoted decorative `ADMIT ONE` from `h2` to styled `p`; real `h2`s now
    head each content section; added tagline under the H1.
  - Google Play badge (404, listing not live) replaced with
    "Android is coming soon" + early-access mailto. Same swap in the new
    closing `GET TALKIES` section.
  - Added ~800 words in the existing `.stub` ticket style: What is
    Talkies, Every watch a stub, Made for Indian cinema, Your year in
    films, 8-question FAQ, closing CTA. Every claim traced to the App
    Store description, `privacy.html` or PITCH.md.
  - In-page `#faq` link added to top nav and footer.
  - `docs/sitemap.xml`: new, 4 canonical URLs.
  - `docs/support.html`, `docs/privacy.html`, `docs/delete-account.html`:
    self-referencing canonicals + OG/Twitter tags.
  - `support@talkies.in` (domain parked, no MX, mail bounces) replaced
    with `info@sakshammittal.com` in `support.html` and
    `delete-account.html`; added a "Get Talkies on the App Store" line to
    support.
  - `docs/img/og.png` (1024x500, 520 KB) replaced with `docs/img/og.jpg`
    (same art and dims, 79 KB, JPEG q82). Tags updated everywhere.
  - Deviation from the approved spec: no 1200x630 re-export. Resizing
    1024x500 art to 1200x630 would stretch or re-crop it; tags declare the
    true 1024x500 dims instead. A designer export at 1200x630 is still
    welcome later.

## Decisions (with reasoning)

- Content depth = full (~800 words). Chosen by the owner over light/tags-only.
- Play badge = "coming soon + email" (owner's words). Revisit the day the
  `in.talkies.talkies` listing goes live: restore the badge.
- No `llms.txt`, no "chunking" rewrites, no inauthentic-mention outreach.
  Google's AI-optimization guide (2026-07-10) says Google Search does not
  use llms.txt or special AI markup; foundations (crawlable, quotable,
  structured) are the lever.
- No FAQ rich-result expectation: Google dropped FAQ rich results
  (May 2026). FAQPage markup stays for machine clarity, not for SERP
  decoration.
- No custom-domain move in this pass: `talkies.in` is parked and its
  ownership is unconfirmed. github.io stays canonical for now.
- No CTR/title tuning: no Search Console data exists yet, so there is
  nothing to tune against.

## Baselines (2026-10-05, before deploy)

- Live page = `main`-era copy ("No account. No ads."). `site:` search does
  not surface the landing page: treated as unindexed (inferred, not
  confirmed; no Search Console access).
- iTunes: `Talkies: Movie Ticket Diary`, v1.0.0, released 2026-10-02,
  0 ratings. Play: `in.talkies.talkies` = 404.
- Name collision: a larger, unrelated "Talkies" (Kannada/Tulu OTT) owns
  generic-name results. Keep "movie ticket diary" attached to the name.

## Owner steps (cannot be done from here)

1. Search Console: add a URL-prefix property for
   `https://saksham1991999.github.io/talkies-app/`, submit `sitemap.xml`,
   then Request Indexing on `/`, `privacy.html`, `support.html`,
   `delete-account.html`. Coverage belongs to the whole subdirectory.
2. Optional: in the `saksham1991999.github.io` repo (the only place a
   host-root robots.txt can live), add one line:
   `Sitemap: https://saksham1991999.github.io/talkies-app/sitemap.xml`
   Needs owner OK, different repo.
3. Deploy = merge `recommendations` to `main` + push. That push also makes
   `delete-account.html` live (the Play submission needs its URL). Ask
   before doing this.

## Open flags and review dates

- [ ] Search Console verified + sitemap submitted (due: deploy week).
- [ ] Re-check `site:` visibility at +2 weeks (2026-10-19), +4 weeks
      (2026-11-02), +8-12 weeks (2026-12-01). Targets: landing page
      indexed, 4/4 URLs indexed.
- [ ] Play listing live? Then restore the Play badge (both spots).
- [ ] Ratings exist? Then (and only then) add `aggregateRating` to the
      SoftwareApplication node. Never invent one.
- [ ] Manual visual check still owed: open `docs/index.html` at 375px and
      desktop widths; confirm guide stubs render, no horizontal scroll.
      (No headless browser in this environment; structural checks passed.)
- [ ] Next coverage step (separate task): "Talkies vs Letterboxd"-style
      page or Hindi landing page, once indexing is confirmed.
