import Image from "next/image";

// The app icon is the logo. Decorative wherever it sits next to the wordmark, so alt="".
// CSS (.app-icon) applies the 22.37% continuous-corner approximation and a hairline ring.
export function AppIcon({ size, priority = false }: { size: number; priority?: boolean }) {
  return (
    <Image
      src="/images/app-icon-256.png"
      alt=""
      width={size}
      height={size}
      className="app-icon"
      priority={priority}
    />
  );
}
