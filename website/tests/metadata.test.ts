import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { OG_IMAGE, PAGES, pageMetadata } from "@/lib/metadata";
import { ROUTES } from "@/lib/site";

// Every page needs a title, a description, a canonical URL, Open Graph and a Twitter card.
// Pages get all of them from pageMetadata() (lib/metadata.ts): either with an entry in PAGES or,
// for the docs MDX pages, with an inline { path, title, description }. This test checks both.

const ROOT = path.resolve(__dirname, "..");

function pageFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const entry = path.join(dir, name);
    if (statSync(entry).isDirectory()) return pageFiles(entry);
    return /^page\.(tsx|mdx)$/.test(name) ? [entry] : [];
  });
}

// The route a page file serves: app/docs/daw/page.mdx -> /docs/daw.
function routeOf(file: string): string {
  const dir = path.relative(path.join(ROOT, "app"), path.dirname(file));
  return dir ? `/${dir.split(path.sep).join("/")}` : "/";
}

type Info = { path: string; title: string; description: string };

// Reads the page's metadata info from its source: PAGES.<key> or an inline object literal.
function infoOf(source: string): Info | undefined {
  const byKey = source.match(/export const metadata = pageMetadata\(PAGES\.(\w+)\)/);
  if (byKey) return (PAGES as Record<string, Info>)[byKey[1]];
  const inline = source.match(
    /export const metadata = pageMetadata\(\{\s*path: "([^"]+)",\s*title: "([^"]+)",\s*description: "([^"]+)",\s*\}\)/,
  );
  if (inline) return { path: inline[1], title: inline[2], description: inline[3] };
  return undefined;
}

const files = pageFiles(path.join(ROOT, "app"));
const cases = files.map((file) => ({
  file: path.relative(ROOT, file),
  route: routeOf(file),
  info: infoOf(readFileSync(file, "utf8")),
}));

describe("page metadata", () => {
  it("finds a page file for every route in the sitemap", () => {
    expect(cases.map((c) => c.route).sort()).toEqual([...ROUTES].sort());
  });

  it.each(cases)("$file sets its metadata with pageMetadata()", ({ info }) => {
    expect(info).toBeDefined();
  });

  it.each(cases)("$file has a title, a description of 155 characters or fewer and its own path", ({ route, info }) => {
    if (!info) return;
    expect(info.path).toBe(route);
    expect(info.title.trim()).not.toBe("");
    expect(info.description.trim()).not.toBe("");
    expect(info.description.length).toBeLessThanOrEqual(155);
    if (route !== "/") expect(info.title).toMatch(/ - ShowRecorder$/);
  });

  it("builds canonical, Open Graph and a Twitter card", () => {
    const meta = pageMetadata(PAGES.privacy);
    expect(meta.title).toEqual({ absolute: PAGES.privacy.title });
    expect(meta.description).toBe(PAGES.privacy.description);
    expect(meta.alternates?.canonical).toBe("/privacy");
    expect(meta.openGraph?.url).toBe("/privacy");
    expect(meta.openGraph?.images).toEqual([OG_IMAGE]);
    expect(meta.twitter).toMatchObject({ card: "summary_large_image" });
  });

  it.each(["mixersX32", "mixersXR18"] as const)("%s uses its own share image for Open Graph and the Twitter card", (key) => {
    const page = PAGES[key];
    const meta = pageMetadata(page);
    expect(meta.openGraph?.images).toEqual([page.image]);
    expect(meta.twitter).toMatchObject({ images: [{ url: page.image.url, alt: page.image.alt }] });
  });

  it.each(["mixersX32", "mixersXR18"] as const)("%s has its own 1200x630 PNG share image in public/", (key) => {
    const image = PAGES[key].image;
    expect(image.url).not.toBe(OG_IMAGE.url);
    expect(image.alt.trim()).not.toBe("");
    const png = readFileSync(path.join(ROOT, "public", image.url));
    expect(png.subarray(1, 4).toString()).toBe("PNG");
    expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([1200, 630]);
    expect([image.width, image.height]).toEqual([1200, 630]);
  });
});
