import { readFileSync } from "node:fs";
import path from "node:path";
import { POSTHOG_ASSETS_HOST, POSTHOG_HOST, POSTHOG_OPTIONS, posthogInitScript } from "@/lib/analytics";

const ROOT = path.resolve(__dirname, "..");

describe("website analytics", () => {
  it("counts pageviews without cookies, autocapture or recordings", () => {
    expect(POSTHOG_OPTIONS).toMatchObject({
      api_host: POSTHOG_HOST,
      persistence: "memory",
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
  });
});
