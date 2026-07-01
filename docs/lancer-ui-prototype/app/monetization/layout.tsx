import type { ReactNode } from "react"
import { VariantNav } from "@/components/variant-nav"

export default function MonetizationLayout({ children }: { children: ReactNode }) {
  return (
    <>
      <VariantNav />
      <main className="pt-14 min-h-screen bg-[#050810]">{children}</main>
    </>
  )
}
