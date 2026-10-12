// Visit counts for showrecorder.app, in the PostHog project "Owned Sites" (shared with Eric's other sites;
// filter by $host). Pageviews only: no cookies or local storage (persistence "memory"), no autocapture,
// no session recordings, no surveys, no person profiles for visitors. The privacy page says so.
// The key is PostHog's public project key, meant to be in page source; it can only send events.

export const POSTHOG_KEY = "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4";
export const POSTHOG_HOST = "https://us.i.posthog.com";
// The loader fetches the PostHog library from here (api_host with "-assets").
export const POSTHOG_ASSETS_HOST = "https://us-assets.i.posthog.com";

export const POSTHOG_OPTIONS = {
  api_host: POSTHOG_HOST,
  persistence: "memory",
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

// PostHog's standard loader snippet, then init. Rendered by app/layout.tsx with next/script.
const LOADER = '!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]);t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com"),p.src+="/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString()+" (stub)"},n="capture identify alias on off once set_config people.set people.set_once unset increment append union track_links track_forms track_pageview register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags addEarlyAccessFeatureCallback updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys getNextSurveyStep".split(" "),o=0;o<n.length;o++)g(u,n[o]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);';

export function posthogInitScript(): string {
  return `${LOADER}\nposthog.init(${JSON.stringify(POSTHOG_KEY)}, ${JSON.stringify(POSTHOG_OPTIONS)});`;
}
