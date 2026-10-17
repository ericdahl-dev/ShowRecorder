import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { CHATWOOT_BASE_URL, CHATWOOT_SETTINGS, CHATWOOT_WEBSITE_TOKEN } from "@/lib/chat";

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

// A minimal browser for lib/chat.ts: records injected scripts, dispatches window events, runs timers by hand.
function fakeBrowser() {
  const handlers: Record<string, (() => void)[]> = {};
  const timers: (() => void)[] = [];
  const scripts: { src: string; async: boolean; onload?: () => void; onerror?: () => void; remove: () => void }[] = [];
  const toggles: (string | undefined)[] = [];
  let runs = 0;
  const win = {
    addEventListener: (name: string, h: () => void) => void (handlers[name] ??= []).push(h),
    removeEventListener: () => {},
    setTimeout: (fn: () => void) => timers.push(fn),
    clearTimeout: () => {},
    chatwootSettings: undefined as unknown,
    chatwootSDK: undefined as unknown,
    $chatwoot: undefined as unknown,
  };
  const doc = {
    createElement: () => {
      const s = { src: "", async: false, remove: () => scripts.splice(scripts.indexOf(s), 1) } as (typeof scripts)[number];
      return s;
    },
    body: { appendChild: (s: (typeof scripts)[number]) => void scripts.push(s) },
  };
  vi.stubGlobal("window", win);
  vi.stubGlobal("document", doc);
  return {
    win,
    scripts,
    toggles,
    runs: () => runs,
    emit: (name: string) => (handlers[name] ?? []).forEach((h) => h()),
    timeout: () => timers.splice(0).forEach((t) => t()),
    // The SDK arriving: it defines chatwootSDK, whose run() creates $chatwoot.
    loadScript: () => {
      win.chatwootSDK = {
        run: () => {
          runs++;
          win.$chatwoot = { toggle: (s?: string) => void toggles.push(s) };
        },
      };
      scripts[0].onload?.();
    },
  };
}

describe("support chat (Chatwoot, click to load)", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  it("keeps the chat server and token as inert constants in the shared loader", () => {
    expect(CHATWOOT_BASE_URL).toBe("https://chatwoot.ericdahl.dev");
    expect(CHATWOOT_WEBSITE_TOKEN).toBe("2Esh9of1eCKs1kXoMVVfy1oY");
    // The bubble design depends on Chatwoot showing its own launcher once loaded; ours hides then.
    expect(CHATWOOT_SETTINGS.hideMessageBubble).toBe(false);
    const source = read("lib", "chat.ts");
    expect(source).toContain("/packs/js/sdk.js");
    expect(source).toMatch(/chatwoot:ready/);
    expect(source).toMatch(/toggle\("open"\)/);
    // The script is created only inside openChat, which only the click handlers call.
    expect(source.indexOf('createElement("script")')).toBeGreaterThan(source.indexOf("export function openChat"));
  });

  it("injects the SDK only on the first click, then opens the chat when it is ready", async () => {
    const b = fakeBrowser();
    const chat = await import("@/lib/chat");
    expect(b.scripts).toHaveLength(0);
    chat.openChat("bubble");
    expect(b.scripts).toHaveLength(1);
    expect(b.scripts[0].src).toBe("https://chatwoot.ericdahl.dev/packs/js/sdk.js");
    expect(chat.chatState()).toEqual({ status: "loading", source: "bubble" });
    // A second click on either control while it loads injects nothing more.
    chat.openChat("support");
    chat.openChat("bubble");
    expect(b.scripts).toHaveLength(1);
    b.loadScript();
    expect(b.runs()).toBe(1);
    expect(b.win.chatwootSettings).toEqual({ hideMessageBubble: false, position: "right", type: "standard" });
    b.emit("chatwoot:ready");
    expect(chat.chatState().status).toBe("loaded");
    expect(b.toggles).toEqual(["open"]);
  });

  it("just opens the chat when the other control already loaded it", async () => {
    const b = fakeBrowser();
    const chat = await import("@/lib/chat");
    chat.openChat("support");
    b.loadScript();
    b.emit("chatwoot:ready");
    chat.openChat("bubble");
    expect(b.scripts).toHaveLength(1);
    expect(b.runs()).toBe(1);
    expect(b.toggles).toEqual(["open", "open"]);
  });

  it("fails over to email for the control that was pressed, and can try again", async () => {
    const b = fakeBrowser();
    const chat = await import("@/lib/chat");
    chat.openChat("bubble");
    b.scripts[0].onerror?.();
    expect(chat.chatState()).toEqual({ status: "failed", source: "bubble" });
    expect(b.scripts).toHaveLength(0);
    chat.openChat("support");
    expect(chat.chatState()).toEqual({ status: "loading", source: "support" });
    expect(b.scripts).toHaveLength(1);
  });

  it("waits for a slow script again rather than injecting a second one", async () => {
    const b = fakeBrowser();
    const chat = await import("@/lib/chat");
    chat.openChat("bubble");
    b.timeout();
    expect(chat.chatState().status).toBe("failed");
    chat.openChat("bubble");
    expect(b.scripts).toHaveLength(1);
    b.loadScript();
    b.emit("chatwoot:ready");
    expect(chat.chatState().status).toBe("loaded");
  });

  it("puts the bubble in the root layout, so it is on every page", () => {
    const layout = read("app", "layout.tsx");
    expect(layout).toMatch(/import \{ ChatBubble \} from "@\/components\/ChatBubble"/);
    expect(layout.match(/<ChatBubble \/>/g)).toHaveLength(1);
    const bubble = read("components", "ChatBubble.tsx");
    expect(bubble).toMatch(/"use client"/);
    expect(bubble).toMatch(/useChat\("bubble"\)/);
    expect(bubble).toMatch(/<button[\s\S]*?aria-label="Chat with ShowRecorder support"/);
    expect(bubble).toMatch(/trackAttrs\("chat_opened"\)/);
    expect(bubble).toMatch(/aria-live="polite"/);
    expect(bubble).toMatch(/CONTACT_EMAIL/);
    // Hidden once loaded: Chatwoot's own launcher is then in the same spot.
    expect(bubble).toMatch(/status === "loaded"\) return null/);
    expect(bubble).not.toMatch(/<img|src=/);
  });

  it("styles the bubble as a fixed launcher in Chatwoot's spot, with motion only when allowed", () => {
    const css = read("app", "globals.css");
    const rule = css.match(/\.chat-bubble \{[^}]+\}/)?.[0] ?? "";
    expect(rule).toMatch(/position: fixed/);
    expect(rule).toMatch(/right: 20px/);
    expect(rule).toMatch(/bottom: 20px/);
    expect(css).toMatch(/\.chat-bubble-button \{[^}]*width: 64px[^}]*height: 64px/);
    // Narrow screens: 48 px (over the 44 px tap target), 16 px offsets, and the footer padding to match.
    const narrow = css.split("@media (max-width: 480px)").slice(1).join("");
    expect(narrow).toMatch(/\.chat-bubble \{\s*right: 16px;\s*bottom: 16px;/);
    expect(narrow).toMatch(/\.chat-bubble-button \{\s*width: 48px;\s*height: 48px;/);
    expect(narrow).toMatch(/\.site-footer \{\s*padding-bottom: 88px;/);
    expect(css).toMatch(/\.chat-bubble-button:focus-visible \{[^}]*outline: 3px solid var\(--focus\)/);
    const motion = css.split("@media (prefers-reduced-motion: no-preference)").slice(1).join("");
    expect(motion).toMatch(/\.chat-bubble-spinner \{\s*animation/);
    expect(css.replace(/@media \(prefers-reduced-motion: no-preference\) \{[\s\S]*?\n\}/g, "")).not.toMatch(/animation: chat-bubble/);
  });

  it("is still on the support page, between Troubleshooting and the email line (#website-review 19), using the shared loader", () => {
    const support = read("app", "support", "page.mdx");
    expect(support).toMatch(/import \{ ChatButton \} from "@\/components\/ChatButton"/);
    const email = support.indexOf("mailto:");
    const button = support.indexOf("<ChatButton />");
    expect(button).toBeLessThan(email);
    expect(button).toBeGreaterThan(support.indexOf("(/docs/troubleshooting)"));
    expect(email).toBeLessThan(support.indexOf("## Getting started"));
    const source = read("components", "ChatButton.tsx");
    expect(source).toMatch(/useChat\("support"\)/);
    expect(source).toMatch(/onClick=\{chat\.open\}/);
    expect(source).toMatch(/CONTACT_EMAIL/);
    expect(source).toMatch(/trackAttrs\("chat_opened"\)/);
    expect(source).not.toContain("sdk.js");
  });

  it("never warms up a connection to the chat server before the click", () => {
    const sources = ["app", "components", "lib"].flatMap((dir) => files(path.join(ROOT, dir)));
    expect(sources.some((f) => f.endsWith(path.join("lib", "chat.ts")))).toBe(true);
    for (const file of sources) {
      if (!/\.(tsx?|mdx)$/.test(file)) continue;
      const text = readFileSync(file, "utf8");
      if (!/chatwoot|lib\/chat"/i.test(text)) continue;
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

  it("is disclosed on the privacy page, for every page", () => {
    const privacy = read("app", "privacy", "page.mdx");
    expect(privacy).toMatch(/## Support chat/);
    expect(privacy).toMatch(/Every page has an optional chat button in the corner, and the support page has a "Chat with us" button\./);
    expect(privacy).toMatch(/Nothing loads until you click one\./);
    expect(privacy).toMatch(/Chatwoot, run on the developer's own server/);
    expect(privacy).toMatch(/a cookie and local storage/);
    expect(privacy).toMatch(/stores nothing in your browser or on your device, unless you open the chat \(see below\)/);
    expect(privacy).toMatch(/and on the chat buttons, and notes which page they were on/);
    expect(privacy).not.toMatch(/The support page has an optional chat/);
    expect(privacy).toMatch(/The ShowRecorder app collects nothing\./);
  });
});
