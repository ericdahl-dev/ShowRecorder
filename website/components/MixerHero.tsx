import { AppStoreBadge } from "@/components/AppStoreBadge";
import { Mark } from "@/components/Mark";

// The top of a mixer page (#482): which mixers, what it does in one sentence, and the call to action with its
// price line, all above the fold on a phone. Styled like the home hero (.hero), without the screenshots column,
// and lined up with the page body below it (.mixer-hero .inner).
// `beta`: the call to action stays on the public beta even after 1.0 is in the App Store (see AppStoreBadge).
export function MixerHero({
  eyebrow,
  title,
  lede,
  price,
  beta = false,
}: {
  eyebrow: string;
  title: string;
  lede: string;
  price: string;
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
            <AppStoreBadge id="app-store-link" beta={beta} />
            <p className="price">{price}</p>
          </div>
        </div>
      </div>
    </section>
  );
}
