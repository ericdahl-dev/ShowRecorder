import { llmsFullTxt } from "@/lib/llms";

// /llms-full.txt: the same facts as /llms.txt plus every feature and every release, on one page (#704).
export const dynamic = "force-static";

export function GET() {
  return new Response(llmsFullTxt(), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
