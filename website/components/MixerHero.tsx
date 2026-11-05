import { AppStoreBadge } from "@/components/AppStoreBadge";
import { BetaLink } from "@/components/BetaLink";
import { Mark } from "@/components/Mark";
import { ctaNote, type AppStoreCampaign } from "@/lib/site";

// The top of a mixer page (#482): which mixers, what it does in one sentence, and the call to action with its
// note on what happens after the click, all above the fold on a phone. Styled like the home hero (.hero), without the screenshots column,
// and lined up with the page body below it (.mixer-hero .inner).
// `beta`: the call to action stays on the public beta even after 1.0 is in the App Store (see AppStoreBadge).
export function MixerHero({
  eyebrow,
  title,
  lede,
  campaign,
  beta = false,
}: {
  eyebrow: string;
  title: string;
  lede: string;
  campaign: AppStoreCampaign;
  beta?: boolean;
}) {
  return (
    <section id="top" aria-labelledby="hero-title" className="hero mixer-hero">
      <div className="wrap">
        <div className="inner">
          <p className="eyebrow">
            <Mark />
            {eyebrow}
          </p>
          <h1 id="hero-title">{title}</h1>
          <p className="lede">{lede}</p>
          <div className="hero-actions">
            <AppStoreBadge id="app-store-link" campaign={campaign} beta={beta} />
            {beta ? null : <BetaLink />}
            <p className="price">{ctaNote(beta)}</p>
          </div>
        </div>
      </div>
    </section>
  );
}
