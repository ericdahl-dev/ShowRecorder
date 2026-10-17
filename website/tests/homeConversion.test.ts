import { readFileSync } from "node:fs";
import path from "node:path";
import { SITE_DESCRIPTION, ctaNote } from "@/lib/site";

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

  it("keeps the XR18 page link in the hero, and puts the Show-Safe line and /compare under the button in the section below the pricing", () => {
    expect(hero).toMatch(/href="\/mixers\/xr18"/);
    const home = read("app", "page.tsx");
    const section = home.slice(home.indexOf('id="email"'), home.indexOf('id="faq"'));
    expect(section).toMatch(/A Take never stops because of a Trial, a limit or a license\./);
    expect(section).toMatch(/href="\/compare"/);
    expect(section.indexOf("<AppStoreBadge")).toBeLessThan(section.indexOf("A Take never stops"));
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

  it("answers what the beta costs: nothing, 90 days per build, Free is every USB Channel", () => {
    expect(home).toMatch(/q: "What does the beta cost\?"/);
    expect(home).toMatch(/expire after 90 days/);
    expect(home).toMatch(/Free records every USB Channel/);
    expect(home).not.toMatch(/so every USB Channel records/);
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

describe("any class-compliant USB mixer records; only Mixer Link is for named mixers (#721)", () => {
  const home = read("app", "page.tsx");
  const hero = home.slice(home.indexOf('<section id="top"'), home.indexOf("</section>", home.indexOf('<section id="top"')));

  it("the hero compatibility line says any class-compliant USB mixer or audio interface", () => {
    const compat = hero.slice(hero.indexOf('className="compat"'), hero.indexOf("</p>", hero.indexOf('className="compat"')));
    expect(compat).toMatch(/Records any class-compliant USB mixer or audio interface\./);
    expect(compat).toMatch(/Mixer Link adds channel names and colors from the/);
    expect(compat).toMatch(/XR18 and MR18/);
    expect(compat).toMatch(/X32 and M32 \(beta\)/);
    expect(compat).toMatch(/iPhone 15 or later/);
  });

  it("the site description, llms.txt and 'What you need' do not say a named mixer is required", () => {
    expect(SITE_DESCRIPTION).toMatch(/class-compliant USB mixer/);
    expect(read("lib", "llms.ts")).toMatch(/a class-compliant USB mixer or audio interface/);
    expect(read("lib", "llms.ts")).not.toMatch(/and a compatible mixer/);
    expect(home).toMatch(/title: "A class-compliant USB mixer"/);
    expect(home).not.toMatch(/title: "A compatible mixer"/);
  });

  it("the 'Which mixers work?' FAQ leads with any class-compliant mixer, then names who gets Mixer Link", () => {
    const faq = home.slice(home.indexOf('q: "Which mixers work?"'), home.indexOf('q: "Can I record an XR18'));
    expect(faq).toMatch(/a: "Any class-compliant USB mixer or audio interface records every channel it sends\./);
    expect(faq).toMatch(/Mixer Link adds channel names and colors for the Behringer X Air XR18 and MR18/);
  });
});
