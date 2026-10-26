# SEO log for the Talkies landing page

Cold-start note: GitHub Pages serves `main`/`docs` at
https://saksham1991999.github.io/talkies-app/.
Work happens on the `recommendations` branch. Nothing here is live until
`recommendations` merges to `main` and pushes.

## Changelog

- 2026-10-26: Multilingual launch correction.
  - `docs/index.html`: every understated language-count claim replaced
    with the true count (45). Touched: JSON-LD `featureList`, JSON-LD
    `inLanguage` (was 8 codes, now all 45 locale codes), the FAQ answer (schema
    and visible copy kept word-for-word identical), the "What is Talkies"
    paragraph, the hero stub body, the "Made for Indian cinema" scripts line,
    and the Hindi screenshot caption + alt text.
  - Added `rel="alternate"` `hreflang="en"` and `hreflang="x-default"`
    pointing at the single English landing page. No translated landing
    pages were created.
  - New paragraph naming what the languages are and stating plainly that
    this page stays in English.
  - FAQ stub serial `Eight answers` renamed `Common questions` so the word
    "Eight" cannot be misread as a language count.
  - No URL changed, so `sitemap.xml` URLs are unchanged; only `lastmod` on
    `/` moved to 2026-10-26.

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

## Multilingual launch (2026-10-26)

What shipped localized:

- **App UI**: 45 languages (`lib/l10n/locale_meta.dart` is the source of
  truth; 44 entries with `ready: true`, English is the template). The
  picker in Settings lists a language only once its ARB is complete, so a
  seeded file never ships as a broken translation. Arabic, Hebrew and Urdu
  are RTL; the layout flips through directional insets and alignments, and
  the printed `WATCHED` / `FDFS` stamp words stay Latin in every locale
  because Tanker has no other script.
- **Store metadata**: 50 locale files in `store/metadata/` (the App Store's
  50 storefront languages), 41 in `store/translations/`, screenshots per
  locale in `store/appstore/*/` and `store/play/*/`.
- **Store listing URLs**: one listing, localized by storefront —
  `https://apps.apple.com/{storefront}/app/id6817738462`, e.g. `/in/`,
  `/us/`, `/jp/`, `/de/`. There is no per-language URL to rank; each
  storefront serves its own metadata.

What did **not** ship localized, and should not for now:

- The landing page. One English page (`lang="en-IN"`), declared with
  `hreflang="en"` and `hreflang="x-default"`. 45 half-translated landing
  pages would be thin duplicate content competing with each other, and the
  page has no indexing history yet to protect.

The measurement that matters: **store page conversion rate by storefront**
(App Store Connect → App Analytics → Metrics → Conversion Rate, split by
storefront and by source). Not keyword rankings for a github.io subdomain,
and not landing-page sessions: the landing page's job is to hand people to
the listing, and the listing is where a localized visit either converts or
does not. If a storefront shows impressions with near-zero conversion,
that is the signal to look at that storefront's screenshots and first two
lines of description, not at English keywords.

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
