import type { ReactNode } from "react";

// A line of copy written as Markdown (only **bold** and [links](href)), rendered as the page's HTML. The same string
// goes into llms-full.txt as it is (HUB_COPY in lib/mixerGuides.ts), so the page and the file say the same thing.
const TOKEN = /\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)/g;

export function InlineMarkdown({ text }: { text: string }) {
  const out: ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(TOKEN)) {
    if (m.index > last) out.push(text.slice(last, m.index));
    out.push(
      m[1] !== undefined ? (
        <strong key={m.index}>{m[1]}</strong>
      ) : (
        <a key={m.index} href={m[3]}>
          {m[2]}
        </a>
      ),
    );
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return <>{out}</>;
}
