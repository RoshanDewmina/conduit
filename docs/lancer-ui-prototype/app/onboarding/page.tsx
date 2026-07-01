"use client"

export default function OnboardingCompare() {
  return (
    <main className="min-h-screen bg-[#050810] px-8 py-10">
      <div className="mb-8 max-w-3xl">
        <p className="text-xs text-blue-400 font-mono uppercase tracking-widest mb-1">Design Review — Workflow 1 of 6</p>
        <h1 className="text-2xl font-bold text-white">Onboarding · Current vs. Proposed</h1>
        <p className="text-sm text-white/50 mt-2">
          Rough wireframes only — not pixel-accurate. Current is traced from the
          real shipped screenshot; proposed is the direction both the Cursor
          audit and the independent verification pass converged on. Nothing in
          Swift has changed yet — this is the review step before implementation.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-8 max-w-4xl">
        <div>
          <p className="text-xs text-white/50 font-mono mb-2 text-center">Current (shipped)</p>
          <iframe
            src="/onboarding/current"
            className="w-full rounded-2xl border border-white/[0.06]"
            style={{ height: 1150, background: "#050810", colorScheme: "dark" }}
          />
        </div>
        <div>
          <p className="text-xs text-blue-400 font-mono mb-2 text-center">Proposed</p>
          <iframe
            src="/onboarding/proposed"
            className="w-full rounded-2xl border border-blue-500/20"
            style={{ height: 1150, background: "#050810", colorScheme: "dark" }}
          />
        </div>
      </div>
    </main>
  )
}
