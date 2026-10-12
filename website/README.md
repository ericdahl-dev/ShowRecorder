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

- `tests/sitemap.test.ts` checks that the sitemap lists `/`, `/privacy` and `/support` as clean
  URLs and that robots.txt points at it.
- `tests/vocab.test.ts` scans the source of `app/` and `components/` for words the product does not
  use: "subscription" (except "No subscription"), "Find mixers" (it is "Find Mixers"),
  "TestFlight", "free trial" (it is "14-day Trial"), "Premium" and the em dash.

`./scripts/verify.sh` at the repo root does not build or test the site; run the commands above.

## Where content lives

| What | Where |
| --- | --- |
| Home page | `app/page.tsx` |
| Privacy policy | `app/privacy/page.mdx` |
| Support | `app/support/page.mdx` |
| Prose styling for the MDX pages | `mdx-components.tsx` (the `wrapper`) |
| Header and footer | `components/Header.tsx`, `components/Footer.tsx` |
| 404 page | `app/not-found.tsx` (exported as `404.html`) |
| Site URL, contact email, issues link, routes | `lib/site.ts` |
| Sitemap and robots.txt | `app/sitemap.ts`, `app/robots.ts` |
| Favicon and Apple touch icon | `app/icon.png` (512 px), `app/apple-icon.png` (180 px) |
| Screenshots | `public/images/` |

MDX pages set their title with `export const metadata = { title: "..." }`. New routes go in
`ROUTES` in `lib/site.ts` so the sitemap lists them.

`APP_STORE_URL` in `lib/site.ts` is `null` until the app is live. Set it to the App Store link
then; pages should show the store badge only when it is set.

### Images

Screenshots are pre-sized JPEGs; `next/image` runs with `unoptimized: true` because a static
export has no image server. From the App Store screenshots:

- `iphone-0N-*.jpg` are 600 px wide, with a 1200 px `@2x` of each for high-density screens
- `ipad-0N-*.jpg` are 900 px wide
- `recording-dark.jpg`, `armed-dark.jpg`, `shows-dark.jpg` and `recording-sunlight.jpg` are copied
  from `docs/images/`
- `app-icon-256.png` is the app icon for the header

To regenerate one, resize by width (`-Z` sets the longest side, which is the height here):

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
- redirects `/privacy/` and `/privacy.html` to `/privacy` (301; the same for support and any other
  trailing slash)
- redirects `www.showrecorder.app` to `https://showrecorder.app` with the same path (301)
- caches `/_next/static/` for a year (immutable, hashed file names) and everything else for
  5 minutes
- gzips text, serves `404.html` for unknown paths, and sends HSTS, CSP, nosniff,
  Referrer-Policy and X-Frame-Options on every response
