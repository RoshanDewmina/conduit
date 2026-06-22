import type { Metadata } from "next";
import { Chakra_Petch, Fira_Code } from "next/font/google";
import Link from "next/link";
import "./globals.css";
import { Toaster } from "@/components/ui/sonner";

const chakraPetch = Chakra_Petch({
  weight: ["400", "500", "600", "700"],
  variable: "--font-display",
  subsets: ["latin"],
});

const firaCode = Fira_Code({
  variable: "--font-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Lancer",
  description: "SSH/agent management dashboard",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${chakraPetch.variable} ${firaCode.variable} dark h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <header className="border-b border-border">
          <nav className="flex items-center gap-6 px-6 h-12 max-w-5xl mx-auto w-full">
            <Link href="/" className="font-display text-sm font-semibold tracking-wider text-foreground uppercase">
              Lancer
            </Link>
            <div className="flex items-center gap-4 ml-auto">
              <Link
                href="/"
                className="font-mono text-xs tracking-wider uppercase text-muted-foreground hover:text-foreground transition-colors"
              >
                Fleet
              </Link>
              <Link
                href="/inbox"
                className="font-mono text-xs tracking-wider uppercase text-muted-foreground hover:text-foreground transition-colors"
              >
                Inbox
              </Link>
            </div>
          </nav>
        </header>
        <main className="flex-1 flex flex-col">{children}</main>
        <Toaster />
      </body>
    </html>
  );
}
