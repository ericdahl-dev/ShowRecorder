import type { MetadataRoute } from "next";
import { PAGE_DATES } from "@/lib/pageDates";
import { RELEASES } from "@/lib/changelog";
import { ROUTES, SITE_URL } from "@/lib/site";

export const dynamic = "force-static";

// Each page's own last-edit date (lib/pageDates.ts, written from git by scripts/page-dates.mjs before each build). A
// route it doesn't know yet falls back to the newest release's date.
const lastModified = (route: string) => PAGE_DATES[route] ?? RELEASES[0].date;

export default function sitemap(): MetadataRoute.Sitemap {
  return ROUTES.map((route) => ({
    url: route === "/" ? SITE_URL : `${SITE_URL}${route}`,
    lastModified: lastModified(route),
    changeFrequency: "monthly",
    priority: route === "/" ? 1 : 0.5,
  }));
}
