import { readFileSync } from "node:fs";
import path from "node:path";
import { BUTTONDOWN_ACTION, DEFAULT_INTEREST, SIGNUP_INTERESTS } from "@/lib/signup";

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("the launch email signup (#719, was the Android signup #404)", () => {
  it("posts to Buttondown's embed endpoint for the ericdahl.dev newsletter", () => {
    expect(BUTTONDOWN_ACTION).toBe("https://buttondown.com/api/emails/embed-subscribe/ericdahl.dev");
  });

  it("offers launch, X32 and Android, and launch is the default", () => {
    expect(SIGNUP_INTERESTS.map((i) => i.value)).toEqual(["launch", "x32", "android"]);
    expect(DEFAULT_INTEREST).toBe("launch");
  });

  it("is a plain form post that works without JavaScript", () => {
    const form = read("components", "SignupForm.tsx");
    expect(form).toMatch(/action=\{BUTTONDOWN_ACTION\}/);
    expect(form).toMatch(/method="post"/);
    expect(form).toMatch(/type="email"\s+name="email"\s+required/);
    expect(form).toMatch(/type="radio"\s+name="metadata__interest"/);
    expect(form).toMatch(/defaultChecked=\{i\.value === DEFAULT_INTEREST\}/);
  });

  it("tells people the terms: confirm first, one-click unsubscribe, no promise of a number of emails", () => {
    const form = read("components", "SignupForm.tsx");
    expect(form).not.toMatch(/two emails/i);
    expect(read("app", "privacy", "page.mdx")).not.toMatch(/two emails/i);
    expect(form).toMatch(/confirm your address first/);
    expect(form).toMatch(/one-click unsubscribe/);
  });

  it("sits under the hero button, with the question above it, and replaces the separate Android section", () => {
    const home = read("app", "page.tsx");
    const hero = home.slice(home.indexOf('<section id="top"'), home.indexOf("</section>", home.indexOf('<section id="top"')));
    expect(hero).toMatch(/<SignupForm \/>/);
    expect(hero.indexOf("<AppStoreBadge")).toBeLessThan(hero.indexOf("<SignupForm"));
    expect(read("components", "SignupForm.tsx")).toMatch(/Not ready to install\? Get the launch email\./);
    expect(home).not.toMatch(/id="android"/);
    expect(home).not.toMatch(/AndroidSignup/);
    expect(home).not.toMatch(/href="#android"/);
  });

  it("is allowed by the CSP's form-action", () => {
    const csp = read("nginx.conf").match(/Content-Security-Policy "([^"]+)"/)?.[1] ?? "";
    expect(csp).toMatch(/form-action 'self' https:\/\/buttondown\.com/);
  });

  it("is disclosed on the privacy page, with no cookies", () => {
    const privacy = read("app", "privacy", "page.mdx");
    expect(privacy).toMatch(/## Launch email list/);
    expect(privacy).toMatch(/Buttondown/);
    expect(privacy).toMatch(/launch, the X32 and M32, or Android/);
    expect(privacy).toMatch(/no cookies/i);
    expect(privacy).not.toMatch(/## Android signup/);
  });
});
