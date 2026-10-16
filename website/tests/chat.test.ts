import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { CHATWOOT_BASE_URL, CHATWOOT_WEBSITE_TOKEN } from "@/components/ChatButton";

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const csp = () => read("nginx.conf").match(/Content-Security-Policy "([^"]+)"/)?.[1] ?? "";
const directive = (name: string) =>
  csp()
    .split(";")
    .map((d) => d.trim())
    .find((d) => d.startsWith(`${name} `)) ?? "";

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = path.join(dir, name);
    return statSync(full).isDirectory() ? files(full) : [full];
  });
}

describe("support chat (Chatwoot, click to load)", () => {
  it("loads the SDK from the chat server only inside the click handler", () => {
    expect(CHATWOOT_BASE_URL).toBe("https://chatwoot.ericdahl.dev");
    expect(CHATWOOT_WEBSITE_TOKEN).toBe("2Esh9of1eCKs1kXoMVVfy1oY");
    const source = read("components", "ChatButton.tsx");
    expect(source).toMatch(/"use client"/);
    expect(source).toContain("/packs/js/sdk.js");
    expect(source).toMatch(/onClick=\{start\}/);
    expect(source).toMatch(/chatwoot:ready/);
    expect(source).toMatch(/toggle\("open"\)/);
    expect(source).toMatch(/CONTACT_EMAIL/);
    expect(source).toMatch(/trackAttrs\("chat_opened"\)/);
  });

  it("is on the support page, beside the email line", () => {
    const support = read("app", "support", "page.mdx");
    expect(support).toMatch(/import \{ ChatButton \} from "@\/components\/ChatButton"/);
    const email = support.indexOf("mailto:");
    const button = support.indexOf("<ChatButton />");
    expect(button).toBeGreaterThan(email);
    expect(button).toBeLessThan(support.indexOf("## Getting started"));
  });

  it("never warms up a connection to the chat server before the click", () => {
    for (const file of files(path.join(ROOT, "app")).concat(files(path.join(ROOT, "components")))) {
      if (!/\.(tsx?|mdx)$/.test(file)) continue;
      const text = readFileSync(file, "utf8");
      if (!text.includes("chatwoot")) continue;
      // No <link rel="preconnect|dns-prefetch|prefetch|preload"> and no react-dom resource hints.
      expect(text, file).not.toMatch(/rel=["{]*["'](?:preconnect|dns-prefetch|prefetch|preload)/);
      expect(text, file).not.toMatch(/\b(?:preconnect|prefetchDNS|preload|preinit)\(/);
    }
  });

  it("is allowed by the CSP, for exactly the chat host", () => {
    expect(directive("script-src")).toBe("script-src 'self' 'unsafe-inline' https://us-assets.i.posthog.com https://chatwoot.ericdahl.dev");
    expect(directive("frame-src")).toBe("frame-src https://chatwoot.ericdahl.dev");
    expect(directive("connect-src")).toBe(
      "connect-src 'self' https://us.i.posthog.com https://us-assets.i.posthog.com https://chatwoot.ericdahl.dev wss://chatwoot.ericdahl.dev",
    );
    expect(directive("img-src")).toBe("img-src 'self' data: https://chatwoot.ericdahl.dev");
    expect(directive("default-src")).toBe("default-src 'self'");
    expect(directive("frame-ancestors")).toBe("frame-ancestors 'none'");
  });

  it("is disclosed on the privacy page", () => {
    const privacy = read("app", "privacy", "page.mdx");
    expect(privacy).toMatch(/## Support chat/);
    expect(privacy).toMatch(/Nothing loads until you click "Chat with us"/);
    expect(privacy).toMatch(/Chatwoot, run by the developer on his own server/);
    expect(privacy).toMatch(/a cookie and local storage/);
    expect(privacy).toMatch(/stores nothing in your browser or on your device, unless you open the support chat/);
  });
});
