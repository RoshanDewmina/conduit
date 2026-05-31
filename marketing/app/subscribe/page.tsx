import { redirect } from "next/navigation";

export default async function SubscribePage({
  searchParams,
}: {
  searchParams: Promise<{ plan?: string }>;
}) {
  const params = await searchParams;
  const plan = params.plan ?? "monthly";

  const backendUrl = process.env.BACKEND_URL;
  if (!backendUrl) {
    throw new Error("BACKEND_URL environment variable is not set.");
  }

  const res = await fetch(`${backendUrl}/billing/checkout`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ plan }),
    cache: "no-store",
  });

  if (!res.ok) {
    throw new Error(
      `Billing backend returned ${res.status} — check that the Cloud Run service is healthy.`
    );
  }

  const { url } = await res.json();

  if (!url || typeof url !== "string") {
    throw new Error(
      "Billing backend did not return a valid Stripe checkout URL."
    );
  }

  redirect(url);
}
