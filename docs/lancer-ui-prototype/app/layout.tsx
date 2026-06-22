import type { Metadata } from "next"
import { GeistSans } from "geist/font/sans"
import { GeistMono } from "geist/font/mono"
import "./globals.css"

export const metadata: Metadata = {
  title: "Lancer UI Prototype",
  description: "Design variants for review",
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${GeistSans.variable} ${GeistMono.variable} bg-[#050810] text-white antialiased`}
        style={{ fontFamily: "var(--font-geist-sans)" }}
      >
        {children}
      </body>
    </html>
  )
}
