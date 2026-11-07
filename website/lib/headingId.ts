import { Children, isValidElement, type ReactNode } from "react";

// The id an MDX heading gets (mdx-components.tsx), so a page can link to its own sections: lowercase, punctuation
// dropped, spaces to hyphens. "X32 on Mac, iPad and iPhone" -> "x32-on-mac-ipad-and-iphone".
export function headingId(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9 -]/g, "")
    .trim()
    .replace(/ +/g, "-");
}

// The plain text of a heading's children (text, or inline elements such as <code> or <strong> around text).
export function textOf(node: ReactNode): string {
  return Children.toArray(node)
    .map((c) => (typeof c === "string" || typeof c === "number" ? String(c) : isValidElement<{ children?: ReactNode }>(c) ? textOf(c.props.children) : ""))
    .join("");
}
