import type { Metadata } from 'next'
import { JetBrains_Mono } from 'next/font/google'

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-jetbrains',
  weight: ['300', '400', '500'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: 'Mainframe — Creative Agency',
  description: 'Good taste tends to find us.',
}

export default function MainframeLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div
      className={jetbrainsMono.variable}
      style={{ fontFamily: 'var(--font-jetbrains), "Courier New", monospace' }}
    >
      {children}
    </div>
  )
}
