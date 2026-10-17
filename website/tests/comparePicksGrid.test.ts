import { readFileSync } from "node:fs";
import path from "node:path";
import { PRODUCTS } from "@/lib/compare";

// Website review item 16: four "when to pick the other one" cards sat 3 + 1 at 1280. Four cards use the two-column grid.

const page = readFileSync(path.resolve(__dirname, "..", "app", "compare", "page.tsx"), "utf8");

describe("compare: when to pick the other one", () => {
  it("lists the other products in a grid that divides evenly", () => {
    const others = PRODUCTS.length - 1;
    const list = page.match(/<ul className="(cards[^"]*)">\s*\{others\.map/)?.[1] ?? "";
    if (others % 3 === 0) expect(list).toContain("cards--3");
    else expect(list).not.toContain("cards--3"); // 3 columns would leave a card alone on the last row
    expect(others).toBe(4);
    expect(list).toBe("cards"); // the default 2-column grid from 768px
  });
});
