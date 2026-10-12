import { readFileSync } from "node:fs";
import path from "node:path";
import { BUTTONDOWN_ACTION, SIGNUP_INTEREST } from "@/lib/androidSignup";

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("Android signup", () => {
  it("posts to Buttondown's embed endpoint for the ericdahl.dev newsletter", () => {
    expect(BUTTONDOWN_ACTION).toBe("https://buttondown.com/api/emails/embed-subscribe/ericdahl.dev");
    expect(SIGNUP_INTEREST).toBe("android");
  });

  it("is a plain form post that works without JavaScript", () => {
    const form = read("components", "AndroidSignup.tsx");
    expect(form).toMatch(/action=\{BUTTONDOWN_ACTION\}/);
    expect(form).toMatch(/method="post"/);
    expect(form).toMatch(/type="email"\s+name="email"\s+required/);
    expect(form).toMatch(/name="metadata__interest" value=\{SIGNUP_INTEREST\}/);
  });

  it("is on the home page", () => {
    const home = read("app", "page.tsx");
    expect(home).toMatch(/<AndroidSignup \/>/);
    expect(home).toMatch(/Is there an Android version\?/);
  });

  it("is allowed by the CSP's form-action", () => {
    const csp = read("nginx.conf").match(/Content-Security-Policy "([^"]+)"/)?.[1] ?? "";
    expect(csp).toMatch(/form-action 'self' https:\/\/buttondown\.com/);
  });

  it("is disclosed on the privacy page", () => {
    const privacy = read("app", "privacy", "page.mdx");
    expect(privacy).toMatch(/Buttondown/);
    expect(privacy).toMatch(/Android/);
  });
});
