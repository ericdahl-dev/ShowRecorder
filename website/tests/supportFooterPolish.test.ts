import { readFileSync } from "node:fs";
import path from "node:path";

// Website review items 19 and 20: /support leads with the self-service fix, then chat, then email, and its answer
// about channel names covers the X32 and M32 too; the footer links sit in two columns on a phone.

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");
const support = read("app", "support", "page.mdx");
const css = read("app", "globals.css");

describe("/support", () => {
  it("offers Troubleshooting first, then chat, then email", () => {
    const at = (s: string) => support.indexOf(s);
    expect(at("(/docs/troubleshooting)")).toBeGreaterThan(-1);
    expect(at("(/docs/troubleshooting)")).toBeLessThan(at("<ChatButton />"));
    expect(at("<ChatButton />")).toBeLessThan(at("mailto:"));
  });

  it("keeps the email address, the GitHub link and one chat button", () => {
    expect(support).toMatch(/mailto:\$\{CONTACT_EMAIL\}/);
    expect(support).toContain("report a problem on GitHub");
    expect(support.match(/<ChatButton \/>/g)).toHaveLength(1);
  });

  it("says the channel names answer covers the X32 and M32 (in the beta) as well as the XR18 and MR18", () => {
    const answer = support.slice(support.indexOf('### The channels are called'), support.indexOf("### The Drive was unplugged"));
    expect(answer).toMatch(/XR18 and MR18/);
    expect(answer).toMatch(/X32 and M32 in the beta/);
  });
});

describe("footer on a phone", () => {
  it("puts the footer links in two columns below 768px, keeping the 44px rows", () => {
    expect(css).toMatch(/\.footer-links\s*\{[^}]*display:\s*grid[^}]*grid-template-columns:\s*repeat\(2,\s*minmax\(0,\s*1fr\)\)/);
    expect(css).toMatch(/\.footer-links a\s*\{[^}]*min-height:\s*44px/);
  });
});
