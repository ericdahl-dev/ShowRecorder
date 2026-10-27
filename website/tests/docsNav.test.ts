import { DOCS } from "@/lib/docs";

// The docs list holds each label on one line, bold for the current page, in the 240 px desktop
// sidebar and on a 320 px phone. "Mixer Link and Find Mixers" (26 characters) is the longest that fits.
describe("the docs list", () => {
  it("keeps every label to 26 characters", () => {
    for (const d of DOCS) expect((d.nav ?? d.title).length, d.slug).toBeLessThanOrEqual(26);
  });
});
