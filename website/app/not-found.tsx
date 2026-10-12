import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Page not found",
  description: "There is no page at this address.",
  robots: { index: false },
};

export default function NotFound() {
  return (
    <section className="wrap not-found">
      <h1>Page not found</h1>
      <p>There is no page at this address.</p>
      <p>
        <Link href="/">Go to the home page</Link>
      </p>
    </section>
  );
}
