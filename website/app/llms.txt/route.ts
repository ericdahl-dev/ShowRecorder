import { llmsTxt } from "@/lib/llms";

// /llms.txt (llmstxt.org): a plain-text map of the site for AI assistants and AI search, with the facts they quote.
// The text is built in lib/llms.ts from the same lists as the sitemap.
export const dynamic = "force-static";

export function GET() {
  return new Response(llmsTxt(), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
