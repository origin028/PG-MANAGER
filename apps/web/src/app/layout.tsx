import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const sans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const mono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: { default: "Origin Living | Co-living and PG homes", template: "%s | Origin Living" },
  description: "Furnished co-living and women-only PG homes. One monthly rent with food, housekeeping and secure entry.",
};

export const viewport: Viewport = { themeColor: "#faf7f0", colorScheme: "light" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${sans.variable} ${mono.variable}`}>
      <body className="min-h-[100dvh] font-sans">{children}</body>
    </html>
  );
}
