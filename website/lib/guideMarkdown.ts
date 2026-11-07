import { readFileSync } from "node:fs";
import path from "node:path";
import { APP_ROWS, CHECKED } from "@/lib/bestApp";
import { MIXER_GUIDES, X32_METHOD_A } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import { SITE_URL } from "@/lib/site";
import { tapPointsAnchor } from "@/components/TapPicks";

// A recording guide's content.mdx as plain Markdown, for llms-full.txt: the same text the page shows, with each
// component swapped for the words it renders and every link to the site made absolute. Read from the MDX file itself,
// so llms-full.txt can't drift from the page. A component this file doesn't know is left in, and the llms-full test
// (tests/llmsFullGuides.test.ts) fails on it: add a replace for it in guideMarkdown().

const abs = (p: string) => (p === "/" ? SITE_URL : SITE_URL + p);

// The text each component renders, in Markdown. Keep these in step with components/TapPicks.tsx and the x32 guide.
const tapPicks = () =>
  MIXER_GUIDES.map((g) => `- **${g.mixer}:** ${g.tapPick} ([${g.short} tap points](${abs(g.path)}#${tapPointsAnchor(g.short)}))`).join("\n");

const x32MethodA = () => X32_METHOD_A.map((s, i) => `${i + 1}. **${s.name}.** ${s.text}`).join("\n");

// components/BestAppTable.tsx: the best-app comparison table and its source list, from APP_ROWS.
const BEST_APP_COLUMNS = [
  ["price", "Price model"],
  ["perChannel", "A file per channel"],
  ["inputs", "Channels at once"],
  ["platforms", "Runs on"],
  ["names", "Channel names from the mixer"],
  ["editing", "Editing on the device"],
] as const;

function bestAppTable(): string {
  const cell = (s: string) => s.replace(/\|/g, "/");
  return [
    `| App | ${BEST_APP_COLUMNS.map(([, label]) => label).join(" | ")} |`,
    `| --- |${" --- |".repeat(BEST_APP_COLUMNS.length)}`,
    ...APP_ROWS.map(
      (r) => `| ${cell(r.name)} (${cell(r.maker)}. [Source](${r.source}), checked ${CHECKED}) | ${BEST_APP_COLUMNS.map(([k]) => cell(r[k])).join(" | ")} |`,
    ),
  ].join("\n");
}

const bestAppSources = () =>
  APP_ROWS.map((r) => `- ${r.name}: [${r.source}](${r.source})${r.extraSource ? ` and [${r.extraSource}](${r.extraSource})` : ""}, checked ${CHECKED}.`).join("\n");

// Markdown links to the site's pages, and to this page's own headings, made absolute.
export function absoluteLinks(md: string, pagePath: string): string {
  return md
    .replace(/\]\(\/([^)]*)\)/g, (_, p: string) => `](${abs("/" + p)})`)
    .replace(/\]\(#([^)]*)\)/g, (_, a: string) => `](${abs(pagePath)}#${a})`);
}

// The guide's file: app/<path>/content.mdx.
export function guideMdx(pagePath: string): string {
  return readFileSync(path.join(process.cwd(), "app", ...pagePath.split("/").filter(Boolean), "content.mdx"), "utf8");
}

export type GuideMarkdown = { title: string; body: string };

// `src` is the MDX, `pagePath` the guide's URL path. `depth` is how many levels to push the guide's own headings
// down: at 2, its H2s become ####, under the guide's own ### title in llms-full.txt.
export function guideMarkdown(src: string, pagePath: string, depth = 2): GuideMarkdown {
  let s = src
    .replace(/\{\/\*[\s\S]*?\*\/\}/g, "")
    .replace(/^import .*$/gm, "")
    .replace(/<Breadcrumbs\b[^>]*\/>/g, "")
    .replace(/<LastChecked\b[^>]*\/>/g, PAGE_DATES[pagePath] ? `Last checked: ${PAGE_DATES[pagePath]}` : "")
    // The call to get the app and the "ask us" link: the Facts at the top of llms-full.txt say both once.
    .replace(/<GetTheApp\b[^>]*\/>/g, "")
    .replace(/<AskUs\s*\/>/g, "")
    .replace(/<TapPicks\s*\/>/g, tapPicks())
    .replace(/<ol>\s*\{X32_METHOD_A\.map[\s\S]*?<\/ol>/g, x32MethodA())
    .replace(/<BestAppTable\s*\/>/g, bestAppTable())
    .replace(/<BestAppSources\s*\/>/g, bestAppSources())
    .replace(/\{CHECKED\}/g, CHECKED)
    .replace(/<details>\s*<summary>([^<]*)<\/summary>/g, "**$1:**")
    .replace(/<\/details>/g, "");
  s = absoluteLinks(s, pagePath);

  const h1 = s.match(/^# (.+)$/m);
  const title = h1 ? h1[1].trim() : pagePath;
  if (h1) s = s.replace(h1[0], "");
  s = s.replace(/^(#{2,6}) /gm, (_, hashes: string) => `${"#".repeat(Math.min(hashes.length + depth, 6))} `);
  const body = s.replace(/\n{3,}/g, "\n\n").trim();
  return { title, body };
}
