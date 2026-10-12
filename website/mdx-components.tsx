import type { MDXComponents } from "mdx/types";

// Required by @next/mdx in the App Router. Every MDX page (privacy, support) renders inside
// this wrapper, so its prose styling lives in one place.
export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    wrapper: ({ children }) => (
      <article className="prose prose-neutral dark:prose-invert mx-auto max-w-3xl px-4 py-12">
        {children}
      </article>
    ),
    ...components,
  };
}
