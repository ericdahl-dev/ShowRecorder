import Image from "next/image";
import Link from "next/link";
import { SITE_NAME } from "@/lib/site";

export function Header() {
  return (
    <header className="border-b border-[var(--border)]">
      <div className="mx-auto flex max-w-5xl items-center gap-3 px-4 py-4">
        <Link href="/" className="flex items-center gap-3 font-semibold">
          <Image
            src="/images/app-icon-256.png"
            alt=""
            width={32}
            height={32}
            className="rounded-lg"
            priority
          />
          <span>{SITE_NAME}</span>
        </Link>
      </div>
    </header>
  );
}
