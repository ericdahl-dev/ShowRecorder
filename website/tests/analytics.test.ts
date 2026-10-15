import { readFileSync } from "node:fs";
import path from "node:path";
import {
  INTERNAL_KEY,
  POSTHOG_ASSETS_HOST,
  POSTHOG_HOST,
  POSTHOG_OPTIONS,
  TRACK_EVENTS,
  clickTrackingScript,
  internalGuard,
  posthogInitScript,
  trackAttrs,
} from "@/lib/analytics";

const ROOT = path.resolve(__dirname, "..");

describe("website analytics", () => {
  it("counts pageviews without cookies, autocapture or recordings", () => {
    expect(POSTHOG_OPTIONS).toMatchObject({
      api_host: POSTHOG_HOST,
      persistence: "memory",
      cookieless_mode: "always",
      autocapture: false,
      disable_session_recording: true,
      disable_surveys: true,
      person_profiles: "identified_only",
      capture_heatmaps: false,
      capture_dead_clicks: false,
      capture_performance: false,
    });
  });

  it("builds an init script with the public project key and those options", () => {
    const script = posthogInitScript();
    expect(script).toMatch(/posthog\.init\("phc_[A-Za-z0-9]+", \{/);
    expect(script).toContain('"persistence":"memory"');
    expect(script).toContain('"cookieless_mode":"always"');
    expect(script).toContain("posthog.capture");
  });

  it("is allowed by the site's Content-Security-Policy", () => {
    const csp = readFileSync(path.join(ROOT, "nginx.conf"), "utf8").match(/Content-Security-Policy "([^"]+)"/)?.[1] ?? "";
    expect(csp).toMatch(new RegExp(`script-src [^;]*${POSTHOG_ASSETS_HOST.replace(/\./g, "\\.")}`));
    expect(csp).toMatch(new RegExp(`connect-src [^;]*${POSTHOG_HOST.replace(/\./g, "\\.")}`));
  });

  it("is disclosed on the privacy page", () => {
    const privacy = readFileSync(path.join(ROOT, "app", "privacy", "page.mdx"), "utf8");
    expect(privacy).toMatch(/## This website/);
    expect(privacy).toMatch(/PostHog/);
    expect(privacy).toMatch(/no cookies/i);
    // Cookieless server hash mode: IP and browser are hashed with a daily salt and not kept.
    expect(privacy).toMatch(/anonymous hash that changes every day/);
    expect(privacy).toMatch(/does not keep the address/);
    expect(privacy).toMatch(/counts clicks on a few links/);
    expect(privacy).not.toMatch(/stores your IP address/);
    expect(privacy).toMatch(/The ShowRecorder app collects nothing/);
  });
});

describe("the owner's own visits", () => {
  // Runs the init script's guard in a fake browser and reports whether PostHog would load.
  function loads(search: string, stored: string | null): { loaded: boolean; stored: string | null } {
    const store = new Map<string, string>(stored === null ? [] : [[INTERNAL_KEY, stored]]);
    const window = {
      location: { search },
      localStorage: {
        getItem: (k: string) => store.get(k) ?? null,
        setItem: (k: string, v: string) => void store.set(k, v),
        removeItem: (k: string) => void store.delete(k),
      },
    };
    let loaded = false;
    new Function("window", "__load", internalGuard("__load()"))(window, () => (loaded = true));
    return { loaded, stored: store.get(INTERNAL_KEY) ?? null };
  }

  it("loads for ordinary visitors and stores nothing", () => {
    expect(loads("", null)).toEqual({ loaded: true, stored: null });
  });

  it("?internal=1 marks this browser and skips PostHog from then on", () => {
    expect(loads("?internal=1", null)).toEqual({ loaded: false, stored: "1" });
    expect(loads("", "1")).toEqual({ loaded: false, stored: "1" });
  });

  it("?internal=0 clears the mark", () => {
    expect(loads("?internal=0", "1")).toEqual({ loaded: true, stored: null });
  });

  it("the init script uses the guard", () => {
    expect(posthogInitScript()).toContain(INTERNAL_KEY);
  });
});

describe("named click events", () => {
  type Handler = (e: unknown) => void;
  // Runs the click listener in a fake page and returns what posthog.capture received.
  function click(link: Record<string, string> | null, pathname: string, withPosthog = true) {
    let handler: Handler = () => {};
    const captured: [string, Record<string, string>][] = [];
    const window = {
      location: { pathname },
      posthog: withPosthog ? { capture: (n: string, p: Record<string, string>) => void captured.push([n, p]) } : undefined,
    };
    const document = { addEventListener: (_: string, h: Handler) => void (handler = h) };
    new Function("window", "document", clickTrackingScript())(window, document);
    const el = link && { getAttribute: (k: string) => link[k] ?? null };
    handler({ target: { closest: () => el } });
    return captured;
  }

  it("sends the event named in data-track with the page path", () => {
    expect(click({ "data-track": "contact_email_clicked" }, "/support")).toEqual([["contact_email_clicked", { path: "/support" }]]);
  });

  it("adds the destination when the link has one", () => {
    expect(click({ ...trackAttrs("join_beta_clicked", "testflight") }, "/")).toEqual([
      ["join_beta_clicked", { path: "/", destination: "testflight" }],
    ]);
  });

  it("sends mixer_page_cta_clicked for the join and App Store links on a mixer page", () => {
    expect(click(trackAttrs("join_beta_clicked", "testflight"), "/mixers/xr18")[0][0]).toBe("mixer_page_cta_clicked");
    expect(click(trackAttrs("app_store_clicked", "app_store"), "/mixers/x32")[0][0]).toBe("mixer_page_cta_clicked");
    expect(click(trackAttrs("contact_email_clicked"), "/mixers/x32")[0][0]).toBe("contact_email_clicked");
  });

  it("counts any link to /compare", () => {
    expect(click({ href: "/compare" }, "/features")).toEqual([["compare_viewed_cta", { path: "/features" }]]);
  });

  it("ignores other links, clicks that are not on a link, and a page without PostHog", () => {
    expect(click({ href: "/docs" }, "/")).toEqual([]);
    expect(click(null, "/")).toEqual([]);
    expect(click({ "data-track": "contact_email_clicked" }, "/", false)).toEqual([]);
  });

  it("only uses the five named events", () => {
    expect([...TRACK_EVENTS]).toEqual([
      "join_beta_clicked",
      "app_store_clicked",
      "compare_viewed_cta",
      "contact_email_clicked",
      "mixer_page_cta_clicked",
    ]);
  });

  it("marks the badge and every mailto link in the source", () => {
    const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
    const badge = read("components", "AppStoreBadge.tsx");
    expect(badge).toMatch(/trackAttrs\("app_store_clicked"/);
    expect(badge).toMatch(/trackAttrs\("join_beta_clicked"/);
    for (const file of [["components", "Footer.tsx"], ["components", "GetBand.tsx"], ["app", "features", "page.tsx"], ["app", "support", "page.mdx"], ["app", "privacy", "page.mdx"]]) {
      const mailto = read(...file).split("\n").filter((l) => l.includes("mailto:"));
      for (const line of mailto) expect(line).toMatch(/contact_email_clicked/);
    }
  });
});
