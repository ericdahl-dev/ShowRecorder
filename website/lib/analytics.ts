// Visit counts for showrecorder.app, in the PostHog project "Owned Sites" (shared with Eric's other sites;
// filter by $host). Pageviews and a few named link clicks: no cookies or local storage (persistence "memory"),
// no autocapture, no session recordings, no surveys, no person profiles for visitors. The privacy page says so.
// cookieless_mode "always" (posthog-js 1.438, checked in the loaded array.js) sends no ID from the browser: PostHog
// derives visitor and session from a hash of IP, browser and a salt it rotates daily, so a page load is no longer a
// new visitor. The project setting "Cookieless server hash mode" (Owned Sites: stateful) must stay on for it.
// The key is PostHog's public project key, meant to be in page source; it can only send events.

export const POSTHOG_KEY = "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4";
export const POSTHOG_HOST = "https://us.i.posthog.com";
// The loader fetches the PostHog library from here (api_host with "-assets").
export const POSTHOG_ASSETS_HOST = "https://us-assets.i.posthog.com";

export const POSTHOG_OPTIONS = {
  api_host: POSTHOG_HOST,
  persistence: "memory",
  cookieless_mode: "always",
  autocapture: false,
  capture_pageview: "history_change",
  capture_pageleave: false,
  disable_session_recording: true,
  disable_surveys: true,
  person_profiles: "identified_only",
  // "Owned Sites" turns these on at the project level for the other sites; off here.
  enable_heatmaps: false,
  capture_heatmaps: false,
  capture_dead_clicks: false,
  capture_performance: false,
  capture_exceptions: false,
} as const;

// Named click events (autocapture stays off). Put trackAttrs(event) on a link; one delegated listener sends
// posthog.capture(event, { path }) when it is clicked. Add `destination` to say where it goes. On /mixers/* pages the
// join-the-beta and App Store links send mixer_page_cta_clicked instead, with the destination ("testflight" or
// "app_store"). Links to /compare send compare_viewed_cta without any attribute.
export const TRACK_EVENTS = [
  "join_beta_clicked",
  "app_store_clicked",
  "compare_viewed_cta",
  "contact_email_clicked",
  "mixer_page_cta_clicked",
] as const;
export type TrackEvent = (typeof TRACK_EVENTS)[number];

export function trackAttrs(event: TrackEvent, destination?: string): Record<string, string> {
  return destination ? { "data-track": event, "data-track-destination": destination } : { "data-track": event };
}

export function clickTrackingScript(): string {
  return `document.addEventListener("click", function (e) {
  var el = e.target && e.target.closest ? e.target.closest("a") : null;
  if (!el || !window.posthog) return;
  var name = el.getAttribute("data-track");
  if (!name && el.getAttribute("href") === "/compare") name = "compare_viewed_cta";
  if (!name) return;
  var path = window.location.pathname;
  var props = { path: path };
  var destination = el.getAttribute("data-track-destination");
  if (destination) props.destination = destination;
  if (path.indexOf("/mixers/") === 0 && (name === "join_beta_clicked" || name === "app_store_clicked")) name = "mixer_page_cta_clicked";
  try { window.posthog.capture(name, props); } catch (err) {}
}, true);`;
}

// PostHog's standard loader snippet, then init. Rendered by app/layout.tsx with next/script.
const LOADER = '!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]);t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com"),p.src+="/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString()+" (stub)"},n="capture identify alias on off once set_config people.set people.set_once unset increment append union track_links track_forms track_pageview register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags addEarlyAccessFeatureCallback updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys getNextSurveyStep".split(" "),o=0;o<n.length;o++)g(u,n[o]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);';

// Eric's own visits: opening any page with ?internal=1 marks that browser (one localStorage key, set only
// by that link) and PostHog never loads there again; ?internal=0 clears it. Ordinary visitors get nothing
// stored. If storage is blocked, the visit is simply counted.
export const INTERNAL_KEY = "showrecorder_internal";

export function internalGuard(load: string): string {
  return `(function () {
  var internal = false;
  try {
    var flag = new URLSearchParams(window.location.search).get("internal");
    if (flag === "1") window.localStorage.setItem(${JSON.stringify(INTERNAL_KEY)}, "1");
    if (flag === "0") window.localStorage.removeItem(${JSON.stringify(INTERNAL_KEY)});
    internal = window.localStorage.getItem(${JSON.stringify(INTERNAL_KEY)}) === "1";
  } catch (e) {}
  if (!internal) { ${load} }
})();`;
}

export function posthogInitScript(): string {
  return internalGuard(`${LOADER}\nposthog.init(${JSON.stringify(POSTHOG_KEY)}, ${JSON.stringify(POSTHOG_OPTIONS)});\n${clickTrackingScript()}`);
}
