import { posthog } from "@/lib/analytics";

// Fails closed: any error or unreachable PostHog means the flag is off.
export async function referralsEnabled(distinctId: string): Promise<boolean> {
  try {
    return (await posthog.isFeatureEnabled("referrals_enabled", distinctId)) === true;
  } catch {
    return false;
  }
}
