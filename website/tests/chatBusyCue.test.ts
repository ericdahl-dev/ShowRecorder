import { readFileSync } from "node:fs";
import path from "node:path";

// Website review item 15 (reduced motion): the bubble's spinner only turns when motion is allowed, so while the chat
// loads the button also looks different without motion (dimmed), the way "Chat with us" on /support already does.

const css = readFileSync(path.resolve(__dirname, "..", "app", "globals.css"), "utf8");

describe("chat bubble while loading", () => {
  it("is dimmed, outside any motion media query", () => {
    expect(css).toMatch(/\.chat-bubble-button\[aria-busy="true"\]\s*\{[^}]*opacity:\s*0\.[5-8]/);
    const rule = css.match(/\.chat-bubble-button\[aria-busy="true"\]\s*\{[^}]*\}/)?.[0] ?? "";
    expect(rule).toMatch(/cursor:\s*progress/);
  });

  it("matches the dimming of the support page's own chat button", () => {
    const button = css.match(/\.chat-button\[aria-busy="true"\]\s*\{[^}]*opacity:\s*([\d.]+)/)?.[1];
    const bubble = css.match(/\.chat-bubble-button\[aria-busy="true"\]\s*\{[^}]*opacity:\s*([\d.]+)/)?.[1];
    expect(bubble).toBe(button);
  });
});
