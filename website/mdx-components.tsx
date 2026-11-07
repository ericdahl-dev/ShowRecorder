import type { MDXComponents } from "mdx/types";
import type { ComponentProps } from "react";
import { headingId, textOf } from "@/lib/headingId";

// Required by @next/mdx in the App Router. Every MDX page (privacy, support, docs) renders inside
// this wrapper, so its prose styling (.doc in globals.css) lives in one place.
// Its h2 and h3 headings get ids from their text (lib/headingId.ts), so links like (#x32-tap-points) reach them.
export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    wrapper: ({ children }) => (
      <div className="wrap">
        <article className="doc">{children}</article>
      </div>
    ),
    h2: ({ id, children, ...props }: ComponentProps<"h2">) => (
      <h2 id={id ?? headingId(textOf(children))} {...props}>
        {children}
      </h2>
    ),
    h3: ({ id, children, ...props }: ComponentProps<"h3">) => (
      <h3 id={id ?? headingId(textOf(children))} {...props}>
        {children}
      </h3>
    ),
    ...components,
  };
}
