import { readFileSync } from "node:fs";
import path from "node:path";
import { DOCS } from "@/lib/docs";
import { llmsTxt } from "@/lib/llms";
import { SITE_URL } from "@/lib/site";

// The troubleshooting page and its links (what Eric asked for: real problems, short step-by-step fixes).

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const page = read("app", "docs", "troubleshooting", "page.mdx");
const section = (title: string) => {
  const start = page.indexOf(`## ${title}`);
  expect(start, `"## ${title}" is missing`).toBeGreaterThan(-1);
  const next = page.indexOf("\n## ", start + 1);
  return page.slice(start, next === -1 ? undefined : next);
};

describe("/docs/troubleshooting", () => {
  it("has a section for each problem", () => {
    for (const title of [
      "The iPhone doesn't see the mixer",
      "Fewer USB Channels than expected",
      "Mixer Link won't connect",
      "The Drive isn't seen or is too slow",
      "TestFlight won't install",
      "Where the files are, and into your DAW",
    ]) {
      expect(page).toContain(`## ${title}`);
    }
  });

  it("the iPhone-doesn't-see-the-mixer fix covers the cable, a powered hub and class-compliant mode", () => {
    const s = section("The iPhone doesn't see the mixer");
    expect(s).toMatch(/USB-B to USB-C/);
    expect(s).toMatch(/powered USB-C hub/);
    expect(s).toMatch(/class-compliant/);
  });

  it("the channel-count fix covers the mixer's own count and the XR18 routing", () => {
    const s = section("Fewer USB Channels than expected");
    expect(s).toMatch(/XR12 and XR16/);
    expect(s).toMatch(/USB 1 to 16/);
    expect(s).toMatch(/aux return/);
  });

  it("the Mixer Link fix covers the network, the IP address, XR18 vs X32 and blocked traffic", () => {
    const s = section("Mixer Link won't connect");
    expect(s).toMatch(/XR18 and MR18/);
    expect(s).toMatch(/X32 and M32/);
    expect(s).toMatch(/Ethernet port/);
    expect(s).toMatch(/Mixer IP address/);
    expect(s).toMatch(/UDP/);
    expect(s).toMatch(/10024/);
    expect(s).toMatch(/10023/);
  });

  it("the Drive fix covers the format, the speed needed and what a slow Drive does", () => {
    const s = section("The Drive isn't seen or is too slow");
    expect(s).toMatch(/exFAT/);
    expect(s).toMatch(/MB\/s/);
    expect(s).toMatch(/Repair/);
  });

  it("the TestFlight fix covers Accept and the Facebook in-app browser", () => {
    const s = section("TestFlight won't install");
    expect(s).toMatch(/Accept/);
    expect(s).toMatch(/Facebook/);
    expect(s).toMatch(/Open in Safari/);
  });

  it("the files section links the DAW page", () => {
    expect(section("Where the files are, and into your DAW")).toMatch(/\]\(\/docs\/daw\)/);
  });

  it("states no channel limit for Free (the limit is changing in #705)", () => {
    expect(page).not.toMatch(/On Free/);
    expect(page).not.toMatch(/2 USB Channels/);
  });

  it("is in DOCS and llms.txt with the same description as the page", async () => {
    const doc = DOCS.find((d) => d.slug === "troubleshooting");
    expect(doc).toBeDefined();
    expect(page).toContain(`description: "${doc!.description}"`);
    expect(doc!.description.length).toBeLessThanOrEqual(200);
    expect(llmsTxt()).toContain(`${SITE_URL}/docs/troubleshooting): ${doc!.description}`);
  });

  it("is linked from /support", () => {
    expect(read("app", "support", "page.mdx")).toMatch(/\]\(\/docs\/troubleshooting\)/);
  });
});
