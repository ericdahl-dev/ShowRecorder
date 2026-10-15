import { readFileSync } from "node:fs";
import path from "node:path";
import { ctaNote } from "@/lib/site";

// Home page conversion work (#719): what the hero says, what happens after the click, the launch list.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");

describe("the line under the call to action (#719)", () => {
  it("says what happens after the click while the button is TestFlight", () => {
    expect(ctaNote(false)).toBe(
      "The beta is free. Opens Apple's TestFlight app: install TestFlight, tap Accept, then Install.",
    );
  });

  it("is on the home hero, every mixer hero and the closing band, and the App Store wording is gone", () => {
    expect(read("app", "page.tsx")).toMatch(/\{ctaNote\(false\)\}/);
    expect(read("components", "MixerHero.tsx")).toMatch(/\{ctaNote\(beta\)\}/);
    expect(read("components", "GetBand.tsx")).toMatch(/\{ctaNote\(beta\)\}/);
    for (const file of [
      read("app", "page.tsx"),
      read("components", "MixerHero.tsx"),
      read("components", "GetBand.tsx"),
      read("app", "mixers", "xr18", "page.tsx"),
      read("app", "mixers", "x32", "page.tsx"),
    ]) {
      expect(file).not.toMatch(/Free to download/);
    }
  });
});

describe("the home hero (#719)", () => {
  const home = read("app", "page.tsx");
  const hero = home.slice(home.indexOf('<section id="top"'), home.indexOf("</section>", home.indexOf('<section id="top"')));

  it("leads with the result and who it is for", () => {
    expect(hero).toMatch(
      /<h1 id="hero-title">Record every channel of your XR18 on your iPhone\. No laptop at the gig\.<\/h1>/,
    );
  });

  it("says which mixers and devices work, under the headline", () => {
    expect(hero).toMatch(/className="compat"/);
    const compat = hero.slice(hero.indexOf('className="compat"'));
    expect(compat).toMatch(/XR18 and MR18/);
    expect(compat).toMatch(/X32 and M32 \(beta\)/);
    expect(compat).toMatch(/iPhone 15 or later/);
    expect(compat).toMatch(/iPad/);
    expect(compat).toMatch(/iOS 26/);
  });

  it("puts the Show-Safe line under the button, and links /compare and the XR18 page", () => {
    expect(hero).toMatch(/A Take never stops because of a Trial, a limit or a license\./);
    expect(hero).toMatch(/href="\/compare"/);
    expect(hero).toMatch(/href="\/mixers\/xr18"/);
    expect(hero.indexOf("<AppStoreBadge")).toBeLessThan(hero.indexOf("A Take never stops"));
  });
});

describe("the home page order and FAQs (#719)", () => {
  const home = read("app", "page.tsx");

  it("runs hero, how a show goes, what you need, Promise, features, pricing, FAQ, then the closing band", () => {
    const at = (needle: string) => home.indexOf(needle, home.indexOf("export default function Home"));
    const order = ['id="top"', 'id="how"', 'id="need"', 'id="promise"', 'id="features"', 'id="pricing"', 'id="faq"', "<GetBand"].map(at);
    expect(order.every((i) => i > -1)).toBe(true);
    expect([...order].sort((a, b) => a - b)).toEqual(order);
  });

  it("answers whether the beta is safe for a real gig, from what the app does", () => {
    expect(home).toMatch(/q: "Is the beta safe for a real gig\?"/);
    expect(home).toMatch(/Files are saved every 2 seconds/);
    expect(home).toMatch(/test Take/);
  });

  it("answers what the beta costs: nothing, 90 days per build, Free is 2 USB Channels", () => {
    expect(home).toMatch(/q: "What does the beta cost\?"/);
    expect(home).toMatch(/expire after 90 days/);
    expect(home).toMatch(/Free records 2 USB Channels/);
  });

  it("does not claim beta recordings carry over", () => {
    expect(home).not.toMatch(/carry over/i);
  });

  it("shows fewer feature cards on phones and links the features page", () => {
    expect(home).toMatch(/card--more/);
    expect(read("app", "globals.css")).toMatch(/max-width: 639px\)[\s\S]{0,80}\.card--more\s*\{\s*display: none/);
    expect(home).toMatch(/href="\/features"/);
  });
});
