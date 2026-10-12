// The "Notify me if ShowRecorder comes to Android" signup (#404, plan on #395: 50 signups by 2027-01-12).
// A plain form post to Buttondown's embed endpoint, so it works with JavaScript off. It uses Eric's
// existing newsletter "ericdahl.dev": a second newsletter needs a paid plan, and the free plan has no tags,
// so each signup also carries metadata interest=android to keep it apart from any later list.
export const BUTTONDOWN_ACTION = "https://buttondown.com/api/emails/embed-subscribe/ericdahl.dev";
export const SIGNUP_INTEREST = "android";
