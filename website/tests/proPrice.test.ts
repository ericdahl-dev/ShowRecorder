import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { softwareApplicationJsonLd } from "@/lib/structuredData";
import { PRO_PRICE, PRO_PRICE_TEXT } from "@/lib/site";

// The Pro price lives in one constant, PRO_PRICE in lib/price.ts (read through lib/site.ts). Every page, the schema and llms.txt read it, so a
// price change is one edit (docs/app-store/app-store-connect-steps.md says to make it).

const ROOT = path.resolve(__dirname, "..");
const SOURCES = ["app", "components", "lib", "mdx-components.tsx"];

function files(p: string): string[] {
  const full = path.join(ROOT, p);
  if (statSync(full).isFile()) return [p];
  return readdirSync(full).flatMap((name) => files(path.join(p, name)));
}

describe("the Pro price comes from one constant", () => {
  it("is $4.99 as text and 4.99 for the schema", () => {
    expect(PRO_PRICE_TEXT).toBe(`$${PRO_PRICE}`);
  });

  it("appears literally nowhere in the site's source outside lib/price.ts", () => {
    const literal = PRO_PRICE.replace(".", "\\.");
    const hits = SOURCES.flatMap(files)
      .filter((f) => /\.(tsx?|mdx?)$/.test(f) && f !== path.join("lib", "price.ts"))
      .filter((f) => new RegExp(`(?<![\\d.])${literal}(?!\\d)`).test(readFileSync(path.join(ROOT, f), "utf8")));
    expect(hits).toEqual([]);
  });

  it("is the price in the Pro offer of the structured data", () => {
    const pro = softwareApplicationJsonLd().offers.find((o) => o.name === "Pro");
    expect(pro?.price).toBe(PRO_PRICE);
  });
});
