import { PAGES } from "@/lib/metadata";
import { guideBySlug, guideTrail } from "@/lib/mixerGuides";
import { PAGE_DATES } from "@/lib/pageDates";
import {
  breadcrumbListJsonLd,
  faqPageJsonLd,
  jsonLdScript,
  mixerApplicationJsonLd,
  techArticleJsonLd,
} from "@/lib/structuredData";

// The structured data every mixer guide carries, from its MIXER_GUIDES entry: Home > Recording guides > the guide,
// its questions (the page shows the same list), the guide as a TechArticle citing its sources, and the app.
export function GuideJsonLd({ slug }: { slug: string }) {
  const guide = guideBySlug(slug);
  if (!guide) throw new Error(`No mixer guide "${slug}" in MIXER_GUIDES`);
  const page = (PAGES as Record<string, (typeof PAGES)["guidesHub"]>)[guide.pageKey];
  const data = [
    breadcrumbListJsonLd(guideTrail(guide.short, guide.path)),
    faqPageJsonLd(guide.faqs),
    techArticleJsonLd({
      page,
      headline: `How to multitrack record a ${guide.mixer}`,
      datePublished: guide.published,
      dateModified: PAGE_DATES[guide.path] ?? guide.published,
      citations: guide.sources,
    }),
    mixerApplicationJsonLd(page),
  ];
  return (
    <>
      {data.map((d, i) => (
        <script key={i} type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLdScript(d) }} />
      ))}
    </>
  );
}
