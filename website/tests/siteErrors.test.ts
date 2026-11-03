import { readFileSync } from "node:fs";
import path from "node:path";
import { GLITCHTIP_HOST, MAX_REPORTS_PER_PAGE, errorReportingScript, glitchtipStoreUrl } from "@/lib/errors";

// Errors in the visitor's browser go to GlitchTip project showrecorder-web (ADR 0007, #1026): only uncaught errors
// from this site's own scripts, a few per page, with the page address but never its query string.
const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

type Listener = (e: unknown) => void;

// Runs the reporter in a fake page and returns the bodies it sent, as JSON.
function page(opts: { beacon?: boolean } = {}) {
  const listeners: Record<string, Listener> = {};
  const sent: { url: string; body: Record<string, unknown> }[] = [];
  const window = {
    addEventListener: (type: string, fn: Listener) => void (listeners[type] = fn),
    location: { origin: "https://showrecorder.app", host: "showrecorder.app", pathname: "/mixers/x32", search: "?ref=fb" },
  };
  const navigator = {
    sendBeacon:
      opts.beacon === false
        ? undefined
        : (url: string, blob: { text: string }) => {
            sent.push({ url, body: JSON.parse(blob.text) });
            return true;
          },
  };
  const fetch = (url: string, init: { body: string }) => void sent.push({ url, body: JSON.parse(init.body) });
  class Blob {
    text: string;
    constructor(parts: string[]) {
      this.text = parts.join("");
    }
  }
  new Function("window", "navigator", "fetch", "Blob", errorReportingScript())(window, navigator, fetch, Blob);
  return { listeners, sent };
}

describe("website error reports", () => {
  it("posts to the showrecorder-web project's store endpoint with its public key", () => {
    expect(glitchtipStoreUrl()).toBe(
      `${GLITCHTIP_HOST}/api/13/store/?sentry_key=8c584ae34c414187b3db70abb76e7e8a&sentry_version=7`,
    );
  });

  it("sends an uncaught error from the site's own script, with the page but not its query string", () => {
    const { listeners, sent } = page();
    const error = Object.assign(new TypeError("x is undefined"), { stack: "TypeError: x is undefined\n  at a.js:1:2" });
    listeners.error({ message: "x is undefined", filename: "https://showrecorder.app/_next/static/chunks/a.js", error });
    expect(sent).toHaveLength(1);
    expect(sent[0].url).toBe(glitchtipStoreUrl());
    const body = sent[0].body as {
      event_id: string;
      platform: string;
      exception: { values: { type: string; value: string }[] };
      request: { url: string };
      tags: { host: string };
    };
    expect(body.event_id).toMatch(/^[0-9a-f]{32}$/);
    expect(body.platform).toBe("javascript");
    expect(body.exception.values[0]).toMatchObject({ type: "TypeError", value: "x is undefined" });
    expect(body.request.url).toBe("https://showrecorder.app/mixers/x32");
    expect(body.tags.host).toBe("showrecorder.app");
  });

  it("sends an unhandled promise rejection", () => {
    const { listeners, sent } = page();
    listeners.unhandledrejection({ reason: new RangeError("bad range") });
    expect((sent[0].body as { exception: { values: { type: string }[] } }).exception.values[0].type).toBe("RangeError");
  });

  it("ignores errors from other sites' scripts and browser extensions", () => {
    const { listeners, sent } = page();
    listeners.error({ message: "Script error.", filename: "" });
    listeners.error({ message: "boom", filename: "chrome-extension://abc/content.js", error: new Error("boom") });
    listeners.error({ message: "boom", filename: "https://us-assets.i.posthog.com/static/array.js", error: new Error("boom") });
    expect(sent).toHaveLength(0);
  });

  it(`sends at most ${MAX_REPORTS_PER_PAGE} per page`, () => {
    const { listeners, sent } = page();
    for (let i = 0; i < MAX_REPORTS_PER_PAGE + 5; i++) listeners.unhandledrejection({ reason: new Error(`n${i}`) });
    expect(sent).toHaveLength(MAX_REPORTS_PER_PAGE);
  });

  it("falls back to fetch where there is no sendBeacon", () => {
    const { listeners, sent } = page({ beacon: false });
    listeners.unhandledrejection({ reason: new Error("no beacon") });
    expect(sent).toHaveLength(1);
  });

  it("is loaded on every page", () => {
    expect(read("app", "layout.tsx")).toMatch(/errorReportingScript\(\)/);
  });

  it("is allowed by the site's Content-Security-Policy", () => {
    const csp = read("nginx.conf").match(/Content-Security-Policy "([^"]+)"/)?.[1] ?? "";
    expect(csp).toMatch(/connect-src [^;]*https:\/\/errors\.ericdahl\.dev/);
  });
});

describe("the privacy page after ADR 0007", () => {
  const privacy = read("app", "privacy", "page.mdx");

  it("says the App Store version collects nothing and test versions send crash reports and usage", () => {
    expect(privacy).toMatch(/The App Store version of ShowRecorder collects nothing\./);
    expect(privacy).toMatch(/Test versions \(TestFlight\) send crash reports and usage/);
    expect(privacy).toMatch(/Share crash reports and usage/);
    expect(privacy).toMatch(/GlitchTip, run on the developer's own server/);
    expect(privacy).toMatch(/random ID/);
    expect(privacy).not.toMatch(/^Nothing\. ShowRecorder has no accounts, no analytics/m);
  });

  it("names what is never sent", () => {
    expect(privacy).toMatch(/never sends your recordings, Show names, notes, channel names or file names/);
  });

  it("says the website reports errors in your browser", () => {
    expect(privacy).toMatch(/If a page hits an error in your browser/);
  });
});
