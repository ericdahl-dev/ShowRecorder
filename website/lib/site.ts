// Site-wide constants. Pages and components read these instead of hard-coding URLs.

export const SITE_NAME = "ShowRecorder";
export const SITE_URL = "https://showrecorder.app";
export const SITE_DESCRIPTION =
  "A live multitrack recorder for iPhone, iPad and Mac that records every channel of your Mixer, named and colored from the Mixer itself.";
export const CONTACT_EMAIL = "showrecorder@ericdahl.dev";
export const ISSUES_URL = "https://github.com/ericdahl-dev/ShowRecorder/issues";

// Fill in with the App Store link when the app is live; while it is null, pages show no store badge.
export const APP_STORE_URL = null as string | null;

// The routes the site exports. sitemap.ts and the footer read this list.
export const ROUTES = ["/", "/privacy", "/support"] as const;
