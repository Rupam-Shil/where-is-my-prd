import { auth } from "@/auth";
import { referralsEnabled } from "@/lib/flags";
import { getOrCreateCode, referralStats } from "@/lib/referral";

export default async function Dashboard() {
  const session = await auth();
  const userId = session?.user?.id;

  let referral: { link: string; rewardedThisMonth: number; totalReferrals: number } | null = null;
  let failed = false;
  if (userId && (await referralsEnabled(userId))) {
    try {
      const code = await getOrCreateCode(userId);
      const base = process.env.NEXT_PUBLIC_APP_URL ?? process.env.AUTH_URL ?? "";
      referral = { link: `${base}/r/${code}`, ...(await referralStats(userId)) };
    } catch {
      failed = true;
    }
  }

  return (
    <main>
      <p>Welcome {session?.user?.email}</p>
      {failed && <p>Couldn&apos;t load your referral link. Refresh to retry.</p>}
      {referral && (
        <section>
          <h2>Invite a friend, you both get $10</h2>
          <input readOnly value={referral.link} />
          <p>{referral.totalReferrals === 0 ? "No referrals yet." : `${referral.totalReferrals} friends joined.`}</p>
          <p>Rewards this month: {referral.rewardedThisMonth}/5</p>
        </section>
      )}
    </main>
  );
}
