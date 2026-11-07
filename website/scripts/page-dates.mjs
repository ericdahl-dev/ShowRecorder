// Writes lib/pageDates.ts: each route's last-edit date, from `git log -1` of the files that make up the page (its
// page.tsx or page.mdx, the MDX next to it, and the lib/ file that holds its copy). The sitemap's lastmod reads it.
//
// Runs before `yarn build` (the prebuild script). It needs the full git history, so it leaves the committed file as it
// is in a shallow clone (CI) or with no git at all (the Docker build Coolify deploys): commit the file it writes.
// A source file with changes not yet committed counts as edited today.
import { execFileSync } from "node:child_process";
import { readdirSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { capDay, localDay } from "./pageDatesLib.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const APP = path.join(ROOT, "app");
const OUT = path.join(ROOT, "lib", "pageDates.ts");

// The lib/ files whose text a page shows, by route.
const EXTRA = {
  "/": ["lib/features.ts", "lib/mixers.ts"],
  "/features": ["lib/features.ts", "lib/mixers.ts"],
  "/compare": ["lib/compare.ts"],
  "/changelog": ["lib/changelog.ts"],
  "/mixers/xr18": ["lib/mixerFaqs.ts"],
  "/mixers/x32": ["lib/mixerFaqs.ts"],
  "/docs": ["lib/docs.ts"],
  "/guides/record": ["lib/mixerGuides.ts"],
  "/guides/best-app-record-digital-mixer-iphone": ["lib/bestApp.ts"],
};

// The mixer recording guides keep their questions and lists in lib/mixerGuides.ts too.
const extraFor = (route) => EXTRA[route] ?? (route.startsWith("/guides/record/") ? ["lib/mixerGuides.ts"] : []);
const TODAY = localDay(new Date());

const git = (...args) => execFileSync("git", args, { cwd: ROOT, encoding: "utf8" }).trim();

function usable() {
  try {
    return git("rev-parse", "--is-shallow-repository") === "false";
  } catch {
    return false;
  }
}

// Each page directory: its route and the files in it (not the pages below it).
function pages(dir) {
  const names = readdirSync(dir);
  const here = names.some((n) => /^page\.(tsx|mdx)$/.test(n))
    ? [{ dir, files: names.filter((n) => /\.(tsx|mdx)$/.test(n) && statSync(path.join(dir, n)).isFile()) }]
    : [];
  return here.concat(names.filter((n) => statSync(path.join(dir, n)).isDirectory()).flatMap((n) => pages(path.join(dir, n))));
}

function routeOf(dir) {
  const rel = path.relative(APP, dir);
  return rel ? `/${rel.split(path.sep).join("/")}` : "/";
}

function lastEdit(files) {
  if (git("status", "--porcelain", "--", ...files)) return TODAY;
  return capDay(git("log", "-1", "--format=%cs", "--", ...files), TODAY);
}

if (!usable()) {
  console.log("page-dates: no full git history here; keeping the committed lib/pageDates.ts");
  process.exit(0);
}

const dates = {};
for (const { dir, files } of pages(APP)) {
  const route = routeOf(dir);
  // The home page's own files only: app/ also holds the layout, which every page shares.
  const own = route === "/" ? ["page.tsx", "home.css"] : files;
  const sources = own.map((f) => path.relative(ROOT, path.join(dir, f))).concat(extraFor(route));
  dates[route] = lastEdit(sources);
}

const lines = Object.keys(dates)
  .sort()
  .map((r) => `  ${JSON.stringify(r)}: ${JSON.stringify(dates[r])},`);
writeFileSync(
  OUT,
  `// Written by scripts/page-dates.mjs (run before each build with full git history): each route's last-edit date,\n` +
    `// for the sitemap's lastmod. Commit it with the page change.\n` +
    `export const PAGE_DATES: Record<string, string> = {\n${lines.join("\n")}\n};\n`,
);
console.log(`page-dates: wrote ${Object.keys(dates).length} routes`);
