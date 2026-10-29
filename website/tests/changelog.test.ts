import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import { RELEASES } from "@/lib/changelog";
import { renderToStaticMarkup } from "react-dom/server";
import ChangelogPage from "@/app/changelog/page";
import { APP_STORE_URL, ROUTES } from "@/lib/site";

const NOTES = path.resolve(__dirname, "..", "..", "docs", "release-notes");

describe("changelog", () => {
  it("lists releases newest first, each with a date and at least one change", () => {
    const dates = RELEASES.map((r) => r.date);
    expect([...dates].sort().reverse()).toEqual(dates);
    for (const r of RELEASES) {
      expect(r.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(r.changes.length).toBeGreaterThan(0);
    }
  });

  // Runs in CI, where the whole repository is checked out; the website's Docker build only builds.
  it.skipIf(!existsSync(NOTES))("has an entry for every 1.x tag with release notes", () => {
    const tagged = readdirSync(NOTES)
      .map((f) => f.match(/^v(1\.\d+\.\d+)\.md$/)?.[1])
      .filter((v): v is string => Boolean(v));
    const listed = RELEASES.map((r) => r.version);
    for (const v of tagged) expect(listed, `docs/release-notes/v${v}.md has no changelog entry`).toContain(v);
  });

<<<<<<< HEAD
  it("leads with 1.1 on the App Store, and the page links to it (#382)", () => {
    expect(RELEASES[0]).toMatchObject({ version: "1.1.18", channel: "App Store" });
=======
  it("leads with 1.0 on the App Store, and the page links to it (#382)", () => {
    expect(RELEASES.find((r) => r.channel === "App Store")).toMatchObject({ version: "1.0.3" });
>>>>>>> origin/main
    expect(renderToStaticMarkup(ChangelogPage())).toContain(`<a href="${APP_STORE_URL}">`);
  });

  it("is a page in the sitemap", () => {
    expect(ROUTES).toContain("/changelog");
  });
});
