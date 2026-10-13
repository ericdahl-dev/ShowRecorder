import { DOCS, docHref } from "@/lib/docs";
import { PAGES } from "@/lib/metadata";
import { REPO_URL, SITE_NAME, SITE_URL, TRADEMARK_LINE } from "@/lib/site";

// /llms.txt (llmstxt.org): a plain-text map of the site for AI assistants and AI search. Built from
// the same lists as the sitemap, so a new docs page shows up here without editing this file.
export const dynamic = "force-static";

export function GET() {
  const link = (title: string, path: string, note?: string) =>
    `- [${title}](${path === "/" ? SITE_URL : SITE_URL + path})${note ? `: ${note}` : ""}`;

  const body = [
    `# ${SITE_NAME}`,
    "",
    `> ${PAGES.home.description}`,
    "",
    "ShowRecorder is an app for iPhone and iPad. It works best with a Behringer X Air XR18 or MR18, which gives 18 channels with names and colors read from the mixer over its Wi-Fi. Other class-compliant USB audio interfaces record too, without names. The Behringer X32 and Midas M32 work in the public beta: 32 USB Channels with names and colors from the mixer, each file named after what is patched to it. They come to the App Store in a later update. It is free to download with a 14-day Trial of everything; Pro is a one-time purchase. No account, and no data is collected.",
    "",
    "## Pages",
    "",
    link("Home", PAGES.home.path, "What ShowRecorder does, what you need, pricing and the FAQ."),
    link("Features", PAGES.features.path, PAGES.features.description),
    link("What's new", PAGES.changelog.path, PAGES.changelog.description),
    link("Support", PAGES.support.path, PAGES.support.description),
    link("Privacy policy", PAGES.privacy.path, PAGES.privacy.description),
    "",
    "## Docs",
    "",
    link("Docs index", "/docs"),
    ...DOCS.map((d) => link(d.title, docHref(d.slug))),
    "",
    "## Optional",
    "",
    `- [Source and issues](${REPO_URL})`,
    "",
    TRADEMARK_LINE,
    "",
  ].join("\n");

  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
