import { trackAttrs } from "@/lib/analytics";
import type { ReactNode } from "react";
import { AppIcon } from "@/components/AppIcon";
import { AppStoreBadge } from "@/components/AppStoreBadge";
import { CONTACT_EMAIL, ctaNote } from "@/lib/site";

// The closing call shared by the home page and the mixer pages (#482): the icon, a heading, a line on where to get
// the app, and the same App Store slot as the hero.
export function GetBand({
  title = "Record your next Show",
  beta = false,
  children,
}: {
  title?: string;
  beta?: boolean;
  children?: ReactNode;
}) {
  return (
    <section id="get" aria-labelledby="get-title" className="section closing">
      <div className="wrap">
        <div className="inner">
          <AppIcon size={96} />
          <h2 id="get-title">{title}</h2>
          <p>
            {children ??
              "ShowRecorder is on the App Store for iPhone and iPad."}
          </p>
          <AppStoreBadge id="app-store-link-footer" beta={beta} />
          <p className="price">{ctaNote(beta)}</p>
          <p className="ask">
            Questions? Email <a href={`mailto:${CONTACT_EMAIL}`} {...trackAttrs("contact_email_clicked")}>{CONTACT_EMAIL}</a>.
          </p>
        </div>
      </div>
    </section>
  );
}
