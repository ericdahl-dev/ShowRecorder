import { readFileSync } from "node:fs";
import path from "node:path";
import { X32_FAQS, XR18_FAQS } from "@/lib/mixerFaqs";
import { X32_GUIDE_FAQS, XR18_GUIDE_FAQS } from "@/lib/mixerGuides";

// Review batch 1, part D: the product pages (/mixers/...) and the recording guides (/guides/record/...) split the
// work. A product page says what ShowRecorder does with the mixer and owns the iPhone and iPad questions; a guide
// owns the mixer's settings and routing. Each fact lives on one page, and the other links to it.

const ROOT = path.resolve(__dirname, "..");
const read = (...p: string[]) => readFileSync(path.join(ROOT, ...p), "utf8");
const section = (mdx: string, h: string) => {
  const start = mdx.indexOf(`## ${h}`);
  const end = mdx.indexOf("\n## ", start + 3);
  return mdx.slice(start, end === -1 ? undefined : end);
};
const prose = (s: string) => s.split("\n").filter((l) => l.trim() && !l.startsWith("#"));

describe("the product pages hand routing to the recording guides", () => {
  const xr18 = read("app", "mixers", "xr18", "content.mdx");
  const x32 = read("app", "mixers", "x32", "content.mdx");

  it("/mixers/xr18 keeps 'Choose what USB records' to two lines and links the guide's tap points", () => {
    const s = section(xr18, "Choose what USB records");
    expect(prose(s.split("18 channels at 48 kHz")[0])).toHaveLength(2);
    expect(s).toContain("](/guides/record/xr18#xr18-tap-points)");
    expect(s).not.toMatch(/does not clearly identify/);
  });

  it("/mixers/xr18 no longer says which inputs USB carries by default", () => {
    expect(xr18).not.toMatch(/16 inputs and the aux line in/);
    expect(XR18_FAQS.map((f) => f.a).join(" ")).not.toMatch(/16 inputs and the aux line in/);
  });

  it("/mixers/x32 keeps 'Choose what USB records' to two lines and links the guide's routing", () => {
    const s = section(x32, "Choose what USB records");
    expect(prose(s.split("32 channels at 48 kHz")[0])).toHaveLength(2);
    expect(s).toContain("](/guides/record/x32#x32-usb-routing)");
  });
});

describe("each question has one home", () => {
  it("the guides leave the iPhone and iPad questions to the product pages", () => {
    for (const f of [...XR18_GUIDE_FAQS, ...X32_GUIDE_FAQS]) expect(f.q).not.toMatch(/iPhone|iPad/);
    expect(XR18_FAQS.some((f) => /iPhone/.test(f.q))).toBe(true);
    expect(X32_FAQS.some((f) => /iPad|iPhone/.test(f.q))).toBe(true);
  });

  it("the XR12 and XR16 question is on the XR18 guide only", () => {
    expect(XR18_GUIDE_FAQS.filter((f) => /XR12|XR16/.test(f.q))).toHaveLength(1);
    expect(XR18_FAQS.filter((f) => /XR12|XR16/.test(f.q))).toHaveLength(0);
  });

  it("the X32 product page and guide agree: no maker word on iPhone or iPad, and only an emulator so far", () => {
    const a = X32_FAQS.find((f) => /iPad|iPhone/.test(f.q))!.a;
    expect(a).not.toMatch(/^Yes/);
    expect(a).toMatch(/Behringer doesn't document iPhone or iPad audio from the card/);
    expect(a).toMatch(/only against an X32 emulator so far/);
    const guide = read("app", "guides", "record", "x32", "content.mdx");
    expect(guide).toMatch(/Behringer doesn't document iPhone or iPad audio from either card/);
    expect(guide).toMatch(/only against an X32 emulator so far/);
  });
});
