import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Page not found",
};

export default function NotFound() {
  return (
    <section className="mx-auto flex max-w-3xl flex-col items-center gap-4 px-4 py-24 text-center">
      <h1 className="text-3xl font-bold">Page not found</h1>
      <p className="text-[var(--muted)]">There is no page at this address.</p>
      <Link href="/" className="underline">
        Go to the home page
      </Link>
    </section>
  );
}
