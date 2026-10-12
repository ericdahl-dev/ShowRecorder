import type { MDXComponents } from "mdx/types";

// Required by @next/mdx in the App Router. Every MDX page (privacy, support, docs) renders inside
// this wrapper, so its prose styling (.doc in globals.css) lives in one place.
export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    wrapper: ({ children }) => (
      <div className="wrap">
        <article className="doc">{children}</article>
      </div>
    ),
    ...components,
  };
}
