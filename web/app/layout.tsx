import type { Metadata } from "next";
import { Bricolage_Grotesque, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-inter",
});

const bricolage = Bricolage_Grotesque({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-display",
});

const jetbrains = JetBrains_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-mono",
});

export const metadata: Metadata = {
  title: "TrailBrowser — your browser, one switcher away",
  description:
    "TrailBrowser is a local-first native macOS browser built with AppKit and WebKit. Fast tabs, bookmarks, passkeys, local history, and an optional AI page assistant.",
  icons: { icon: "/assets/trailbrowser-icon.svg" },
  openGraph: {
    title: "TrailBrowser — your browser, one switcher away",
    description:
      "Local-first native macOS browser with fast tabs, bookmarks, passkeys, local history, and an optional AI page assistant.",
    url: "https://github.com/yug-space/trailbrowser",
    siteName: "TrailBrowser",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body
        className={`${inter.variable} ${bricolage.variable} ${jetbrains.variable}`}
      >
        {children}
      </body>
    </html>
  );
}
