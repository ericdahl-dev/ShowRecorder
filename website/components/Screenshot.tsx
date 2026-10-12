import type { Shot } from "@/lib/screenshots";

type Props = {
  shot: { dark: Shot; light: Shot };
  // CSS sizes for the displayed width, used to pick 1x or 2x.
  sizes: string;
  // The hero's images load eagerly with high priority; everything else is lazy.
  priority?: boolean;
};

// A screenshot in a CSS device frame, matched to the theme. When the Dark and light images differ,
// both frames are in the HTML and CSS (.only-dark / .only-light) shows one. Below the fold the
// light one is loading="lazy", so on the Dark site its display:none copy is never downloaded. In
// the hero (priority) both load eagerly, so the light hero does not pop in late; only the Dark one,
// the default, gets fetchpriority="high".
//
// Plain <img> rather than next/image: the export is unoptimized anyway, and this keeps the
// explicit 1x/2x srcset for the pre-sized files.
export function Screenshot({ shot, sizes, priority = false }: Props) {
  const same = shot.dark.src === shot.light.src;
  if (same) return <Frame shot={shot.dark} sizes={sizes} eager={priority} />;
  return (
    <>
      <Frame shot={shot.dark} sizes={sizes} eager={priority} className="only-dark" />
      <Frame shot={shot.light} sizes={sizes} eager={priority} high={false} className="only-light" />
    </>
  );
}

function Frame({
  shot,
  sizes,
  eager,
  high = eager,
  className = "",
}: {
  shot: Shot;
  sizes: string;
  eager: boolean;
  // fetchpriority="high"; defaults to eager.
  high?: boolean;
  className?: string;
}) {
  const srcSet = shot.src2x ? `${shot.src} ${shot.width}w, ${shot.src2x} ${shot.width * 2}w` : undefined;
  return (
    <div className={`device device--${shot.device} ${className}`.trim()}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={shot.src}
        srcSet={srcSet}
        sizes={srcSet ? sizes : undefined}
        width={shot.width}
        height={shot.height}
        alt={shot.alt}
        loading={eager ? "eager" : "lazy"}
        fetchPriority={high ? "high" : undefined}
        decoding="async"
      />
    </div>
  );
}
