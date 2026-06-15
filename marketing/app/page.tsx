import SiteNav from "@/components/site/site-nav";
import SiteFooter from "@/components/site/site-footer";
import HeroBackdrop from "@/components/hero/hero-backdrop";
import HeroSection from "@/components/sections/hero-section";
import ProblemSection from "@/components/sections/problem-section";
import ApprovalCardSection from "@/components/sections/approval-card-section";
import PolicySection from "@/components/sections/policy-section";
import ActivitySection from "@/components/sections/activity-section";
import HowItWorksSection from "@/components/sections/how-it-works-section";
import WhyConduitSection from "@/components/sections/why-conduit-section";
import ProofBandSection from "@/components/sections/proof-band-section";
import PricingSection from "@/components/sections/pricing-section";
import TrustSection from "@/components/sections/trust-section";
import FinalCtaSection from "@/components/sections/final-cta-section";
import FaqSection from "@/components/sections/faq-section";

export default function Home() {
  return (
    <div className="relative flex flex-col min-h-screen">
      <HeroBackdrop />

      <div className="relative z-10 flex flex-col min-h-screen">
        <SiteNav />
        <main className="flex-1">
          <HeroSection />
          <ProblemSection />
          <ApprovalCardSection />
          <PolicySection />
          <ActivitySection />
          <HowItWorksSection />
          <WhyConduitSection />
          <ProofBandSection />
          <PricingSection />
          <TrustSection />
          <FinalCtaSection />
          <FaqSection />
        </main>
        <SiteFooter />
      </div>
    </div>
  );
}
