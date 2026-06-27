import type { Metadata } from "next";
import { Chakra_Petch, Fira_Code } from "next/font/google";
import "./globals.css";

const chakra = Chakra_Petch({
  variable: "--font-chakra",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
});

const fira = Fira_Code({
  variable: "--font-fira",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  display: "swap",
});

const TITLE = "Lancer — Approve your agents. Keep your code.";
const DESCRIPTION =
  "Lancer is a phone-first approval, policy, and audit layer for AI coding agents — Claude Code, Codex, and opencode. Risky actions pause and ping your phone; safe actions auto-run by your policy. Your code never leaves your machine.";

export const metadata: Metadata = {
  metadataBase: new URL("https://conduit.dev"),
  title: TITLE,
  description: DESCRIPTION,
  openGraph: {
    title: TITLE,
    description: DESCRIPTION,
    url: "https://conduit.dev",
    siteName: "Lancer",
    // Add public/og.png (1200x630) before launch — referenced here as the OG image.
    images: [{ url: "/og.png", width: 1200, height: 630, alt: TITLE }],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESCRIPTION,
    images: ["/og.png"],
  },
  icons: {
    // Add public/icon.png (512x512) before launch.
    icon: "/icon.png",
    apple: "/icon.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${chakra.variable} ${fira.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-bg text-fg">{children}</body>
    </html>
  );
}
