import type { MetadataRoute } from "next";
import { RELEASES } from "@/lib/changelog";
import { ROUTES, SITE_URL } from "@/lib/site";

export const dynamic = "force-static";

// The site changes with each release (the changelog, features and docs move together), so every page carries the date of
// the newest release in lib/changelog.ts. It moves when a release is added; it is not a per-page edit date.
const LAST_MODIFIED = RELEASES[0].date;

export default function sitemap(): MetadataRoute.Sitemap {
  return ROUTES.map((route) => ({
    url: route === "/" ? SITE_URL : `${SITE_URL}${route}`,
    lastModified: LAST_MODIFIED,
    changeFrequency: "monthly",
    priority: route === "/" ? 1 : 0.5,
  }));
}
