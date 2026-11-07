import { headingId } from "@/lib/headingId";
import { MIXER_GUIDES } from "@/lib/mixerGuides";

// The tap-point guide's "per mixer" list: the setting each mixer guide recommends for a multitrack, linking to that
// guide's tap points. Built from MIXER_GUIDES, so a new guide shows up here too.
// The id the guide gives its "<short> tap points" heading (a short name can have spaces: "L-12 and L-20").
export const tapPointsAnchor = (short: string) => headingId(`${short} tap points`);

export function TapPicks() {
  if (!MIXER_GUIDES.length) return null;
  return (
    <ul className="tap-picks">
      {MIXER_GUIDES.map((g) => (
        <li key={g.slug}>
          <strong>{g.mixer}:</strong> {g.tapPick} (<a href={`${g.path}#${tapPointsAnchor(g.short)}`}>{g.short} tap points</a>)
        </li>
      ))}
    </ul>
  );
}
