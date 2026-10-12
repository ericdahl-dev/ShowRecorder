import { fileURLToPath } from "node:url";
import createMDX from "@next/mdx";

/** @type {import('next').NextConfig} */
const nextConfig = {
  // A static export: `yarn build` writes the whole site to out/, which nginx serves.
  output: "export",
  // No image server in a static export; screenshots are pre-sized in public/images.
  images: { unoptimized: true },
  // Writes privacy.html rather than privacy/index.html; nginx serves the clean URL /privacy.
  trailingSlash: false,
  reactStrictMode: true,
  pageExtensions: ["js", "jsx", "ts", "tsx", "md", "mdx"],
  // website/ is its own project inside the app repo; stop Next guessing a root from parent lockfiles.
  turbopack: { root: fileURLToPath(new URL(".", import.meta.url)) },
};

const withMDX = createMDX({
  extension: /\.mdx?$/,
});

export default withMDX(nextConfig);
