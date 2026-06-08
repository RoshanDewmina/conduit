import { VariantNav } from "@/components/variant-nav"

export default function ScreenLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <VariantNav />
      <main className="pt-14 min-h-screen flex items-center justify-center bg-[#050810]">
        {children}
      </main>
    </>
  )
}
