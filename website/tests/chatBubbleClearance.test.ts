import { readFileSync } from "node:fs";
import path from "node:path";
import { bubbleVisible } from "@/lib/chat";

// The launcher bubble must not sit on text: it is hidden where the page has its own "Chat with us" button, and the
// footer leaves room so the last line and the footer links can always scroll clear of it.

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");

describe("bubbleVisible", () => {
  it("is false on /support, with or without a trailing slash", () => {
    expect(bubbleVisible("/support")).toBe(false);
    expect(bubbleVisible("/support/")).toBe(false);
  });

  it("is true on every other page, including look-alike paths", () => {
    for (const p of ["/", "/docs", "/docs/troubleshooting", "/compare", "/supporters", "/docs/support"]) {
      expect(bubbleVisible(p)).toBe(true);
    }
  });

  it("is true when the path is not known yet", () => {
    expect(bubbleVisible(null)).toBe(true);
  });
});

describe("the bubble component and footer", () => {
  it("ChatBubble asks bubbleVisible for the current path", () => {
    const src = read("components", "ChatBubble.tsx");
    expect(src).toMatch(/usePathname/);
    expect(src).toMatch(/bubbleVisible\(pathname\)/);
  });

  it("the footer's bottom padding clears the bubble (64px plus 20px), and a phone's (48px plus 16px)", () => {
    const css = read("app", "globals.css");
    expect(css).toMatch(/@media \(max-width: 480px\) \{\s*\.site-footer \{\s*padding-bottom:\s*(6\d|[7-9]\d|1\d\d)px/);
    const footer = css.match(/\.site-footer\s*\{[^}]*\}/)?.[0] ?? "";
    expect(footer).toMatch(/padding-block:\s*\d+px\s+(9\d|1\d\d)px/);
  });
});
