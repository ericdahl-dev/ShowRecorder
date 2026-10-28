// The release news signup (was the launch email, #719; it began as the "Notify me if ShowRecorder comes to Android" form, #404).
// A plain form post to Buttondown's embed endpoint, so it works with JavaScript off. It uses Eric's
// existing newsletter "ericdahl.dev": a second newsletter needs a paid plan, and the free plan has no tags,
// so each signup carries metadata interest=launch, x32 or android to keep the lists apart.
export const BUTTONDOWN_ACTION = "https://buttondown.com/api/emails/embed-subscribe/ericdahl.dev";

export const SIGNUP_INTERESTS = [
  { value: "launch", label: "Release news: new versions and the Mac app" },
  { value: "x32", label: "The X32 and M32 coming to the App Store" },
  { value: "android", label: "An Android version, if it happens" },
] as const;

export const DEFAULT_INTEREST = "launch";
