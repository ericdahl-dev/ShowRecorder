import { readFileSync } from "node:fs";
import path from "node:path";
import { SIGNUP_INTERESTS } from "@/lib/signup";

// The hero keeps only the TestFlight button (Eric, via cos). Everything that sat under it (the button's helper line,
// the Show-Safe line, the launch email form, the two links) moved to a section after the pricing cards, with its own
// TestFlight button. The form itself and its tracking did not change.

const read = (...p: string[]) => readFileSync(path.resolve(__dirname, "..", ...p), "utf8");
const home = read("app", "page.tsx");
const body = home.slice(home.indexOf("export default function Home"));
const hero = body.slice(body.indexOf('id="top"'), body.indexOf('id="how"'));
const section = body.slice(body.indexOf('id="email"'), body.indexOf('id="faq"'));

describe("hero", () => {
  it("has only the TestFlight button under the lede: no helper line, no Show-Safe line, no form, no links", () => {
    expect(hero.match(/<AppStoreBadge/g)).toHaveLength(1);
    expect(hero).toContain('<AppStoreBadge id="app-store-link"');
    for (const gone of ["ctaNote", "A Take never stops", "<SignupForm", "see-need", "hero-links"]) {
      expect(hero).not.toContain(gone);
    }
  });
});

describe("the section below the pricing cards", () => {
  it("comes after pricing and before the FAQ, once", () => {
    const at = (s: string) => body.indexOf(s);
    expect(at('id="pricing"')).toBeLessThan(at('id="email"'));
    expect(at('id="email"')).toBeLessThan(at('id="faq"'));
    expect(body.match(/id="email"/g)).toHaveLength(1);
  });

  it("holds its own TestFlight button (the same component, so it also sends join_beta_clicked), the helper line, the Show-Safe line, the form and both links, in that order", () => {
    const at = (s: string) => section.indexOf(s);
    const order = ['<AppStoreBadge id="app-store-link-email"', "{ctaNote(false)}", "A Take never stops because of a Trial, a limit or a license.", "<SignupForm />", 'href="#need"', 'href="/compare"'].map(at);
    expect(order.every((i) => i > -1)).toBe(true);
    expect([...order].sort((a, b) => a - b)).toEqual(order);
    expect(read("components", "AppStoreBadge.tsx")).toContain('trackAttrs("join_beta_clicked"');
  });

  it("keeps every form option, Android included, and its tracking", () => {
    expect(SIGNUP_INTERESTS.map((i) => i.value)).toContain("android");
    const form = read("components", "SignupForm.tsx");
    expect(form).toContain('track("signup_view")');
    expect(form).toContain('track("signup_submit"');
    expect(form).toContain("SIGNUP_INTERESTS.map");
  });
});
