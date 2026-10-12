# showrecorder.app

The product site for ShowRecorder: a static Next.js site (App Router, TypeScript, Tailwind CSS 4,
MDX) exported to plain HTML and served by nginx. It lives in this repo beside the app, but it is
its own project with its own dependencies, and nothing in the Xcode project reads it.

## Requirements

- Node 22 (`.nvmrc`; anything from 20.9 works)
- Corepack, which supplies Yarn 4.12.0 from the `packageManager` field: run `corepack enable` once

## Build

```sh
cd website
yarn install --immutable
yarn build        # writes the whole site to out/
```

`out/` holds `index.html`, `privacy.html`, `support.html`, `404.html`, `sitemap.xml`,
`robots.txt`, the icons, `images/` and `_next/static/`.

## Preview

- `yarn dev` runs the dev server at http://localhost:3000 with live reload.
- `yarn start` serves the last `yarn build` from `out/` (with the `serve` package; it does not
  apply the nginx rules).
- To check exactly what production serves, build and run the Docker image:

  ```sh
  docker build -t showrecorder-site website/
  docker run --rm -p 8350:80 showrecorder-site   # http://localhost:8350
  ```

## Tests and lint

```sh
yarn test:run     # vitest, once (`yarn test` watches)
yarn lint         # eslint with eslint-config-next
```

- `tests/sitemap.test.ts` checks that the sitemap lists every page (home, features, docs, support,
  privacy) as a clean URL, that every `app/docs/<slug>/page.mdx` is in `DOCS` (`lib/docs.ts`), and
  that robots.txt points at the sitemap.
- `tests/metadata.test.ts` checks that every `page.tsx` and `page.mdx` sets its metadata with
  `pageMetadata()` (title, description of 155 characters or fewer, canonical, Open Graph, Twitter
  card) and that the pages match the sitemap.
- `tests/vocab.test.ts` scans `app/` (including every MDX page), `components/` and `lib/` for words
  the product does not use: "subscription" (except "No subscription"), "Find mixers" (it is "Find
  Mixers"), "TestFlight", "free trial" (it is "14-day Trial"), "Premium", the em dash, "iPhone, iPad
  and Mac", and a capital "Mixer" outside "Mixer Link", "Find Mixers" and the app's quoted UI strings
  in bold in MDX.

`./scripts/verify.sh` at the repo root does not build or test the site; run the commands above.

## Where content lives

| What | Where |
| --- | --- |
| Home page | `app/page.tsx` |
| Features page | `app/features/page.tsx`, content in `lib/features.ts` |
| Docs | `app/docs/page.mdx` (index), `app/docs/<slug>/page.mdx`, the list in `lib/docs.ts`, the shell in `app/docs/layout.tsx` |
| Privacy policy | `app/privacy/page.mdx` |
| Support | `app/support/page.mdx` |
| Titles, descriptions, canonical, Open Graph, Twitter card | `lib/metadata.ts` (`PAGES`, `pageMetadata()`) |
| Social image (1200 x 630) | `public/og-image.png` |
| Design tokens and all styles | `app/globals.css` |
| Prose styling for the MDX pages | `.doc` in `app/globals.css`, applied by `mdx-components.tsx` |
| Header, footer, App Store slot, screenshots | `components/` |
| Dark/light theme script | `lib/theme.ts` (inlined in `app/layout.tsx`) |
| Screenshot choices and alt text | `lib/screenshots.ts` |
| 404 page | `app/not-found.tsx` (exported as `404.html`) |
| Site URL, contact email, issues link, routes, nav | `lib/site.ts` |
| Sitemap and robots.txt | `app/sitemap.ts`, `app/robots.ts` |
| Favicon and Apple touch icon | `app/icon.png` (512 px), `app/apple-icon.png` (180 px) |
| Screenshots | `public/images/` |

Every page sets its metadata with `pageMetadata()` from `lib/metadata.ts`, so it gets a canonical
URL and the shared Open Graph image. New routes go in `ROUTES` in `lib/site.ts` (docs pages in
`DOCS` in `lib/docs.ts`) so the sitemap lists them.

`APP_STORE_URL` in `lib/site.ts` is `null` until the app is live; the App Store slots then read
"Coming soon to the App Store" and are not links. `components/AppStoreBadge.tsx` says how to swap in
Apple's official badge.

### Themes

The site is Dark by default. The sun button in the header switches to the light (Sunlight) theme
and remembers it in `localStorage`; a small inline script (`lib/theme.ts`) applies the choice before
first paint. It is the site's only script of its own, and the page works without it (Dark). Tokens
are on `:root` (Dark) and `:root[data-theme="light"]` in `app/globals.css`; the theme never follows
`prefers-color-scheme`. Screenshots come in Dark and light pairs and CSS shows the one for the
current theme.

### Images

Screenshots are pre-sized JPEGs shown with plain `<img srcset>` (`components/Screenshot.tsx`); a
static export has no image server. From the App Store screenshots:

- `iphone-0N-*.jpg` (light) and `iphone-dark-0N-*.jpg` (Dark, no 05) are 600 px wide, with a
  1200 px `@2x` of each for high-density screens
- `ipad-01-recording.jpg` (Dark) and `ipad-05-sunlight.jpg` are 900 px wide, for the hero
- `app-icon-256.png` is the app icon for the header

To regenerate one, resize by width:

```sh
sips -s format jpeg -s formatOptions 80 --resampleWidth 600 01-recording.png --out public/images/iphone-01-recording.jpg
```

## Deploy (Coolify)

The `Dockerfile` builds the export with Node 22 and serves `out/` from nginx 1.27 using
`nginx.conf`.

| Coolify setting | Value |
| --- | --- |
| Build pack | Dockerfile |
| Base directory | `/website` |
| Dockerfile location | `/website/Dockerfile` |
| Exposed port | `80` |
| Domains | `https://showrecorder.app`, `https://www.showrecorder.app` |

Coolify's proxy terminates TLS. nginx then:

- serves clean URLs: `/privacy` from `privacy.html`
- redirects any trailing slash and any `.html` address to the clean URL (301): `/privacy/` and
  `/privacy.html` to `/privacy`, `/docs/usb-drive.html` to `/docs/usb-drive`, `/index.html` to `/`
- redirects `www.showrecorder.app` to `https://showrecorder.app` with the same path (301)
- caches `/_next/static/` for a year (immutable, hashed file names) and everything else for
  5 minutes
- gzips text, serves `404.html` for unknown paths, and sends HSTS, CSP, nosniff,
  Referrer-Policy and X-Frame-Options on every response, with no nginx version in the `Server`
  header (`server_tokens off`)

Internal links are plain `<a>`, not `next/link`: every click is a full page load (nothing is
prefetched), so the inline script marks the current page's links on every page.
