import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://conduit.dev"),
  title: "Conduit — SSH Agent Terminal for iOS",
  description:
    "Run AI agents over SSH from your iPhone. Warp-style blocks, Inbox approvals, BYO-host.",
  openGraph: {
    title: "Conduit — SSH Agent Terminal for iOS",
    description:
      "Run AI agents over SSH from your iPhone. Warp-style blocks, Inbox approvals, BYO-host.",
    url: "https://conduit.dev",
    siteName: "Conduit",
    // Add public/og.png (1200x630) before launch — referenced here as the OG image.
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Conduit — SSH Agent Terminal for iOS",
      },
    ],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Conduit — SSH Agent Terminal for iOS",
    description:
      "Run AI agents over SSH from your iPhone. Warp-style blocks, Inbox approvals, BYO-host.",
    images: ["/og.png"],
  },
  icons: {
    // Add public/icon.png (512x512) before launch — referenced here as the app icon.
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
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-zinc-950 text-zinc-100">
        {children}
      </body>
    </html>
  );
}
