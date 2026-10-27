import { createHash, randomBytes } from "crypto";
import { Prisma } from "@prisma/client";
import { db } from "@/lib/db";
import { posthog } from "@/lib/analytics";
import { ratelimit } from "@/lib/ratelimit";
import { normalizeEmail } from "@/lib/email";
import { referralsEnabled } from "@/lib/flags";

export const REWARD_CENTS = 1000;
export const MONTHLY_CAP = 5;
export const CODE_RE = /^[A-Z2-7]{8}$/;

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function newCode(): string {
  return Array.from(randomBytes(8), (b) => ALPHABET[b % 32]).join("");
}

export const hashIp = (ip: string) => createHash("sha256").update(ip).digest("hex").slice(0, 16);

function monthStartUtc(now = new Date()) {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
}

export async function getOrCreateCode(userId: string): Promise<string> {
  const user = await db.user.findUniqueOrThrow({ where: { id: userId }, select: { referralCode: true } });
  if (user.referralCode) return user.referralCode;
  for (let i = 0; i < 5; i++) {
    try {
      // Only set while still null, so concurrent first views converge on one code.
      await db.user.updateMany({ where: { id: userId, referralCode: null }, data: { referralCode: newCode() } });
      break;
    } catch (e) {
      // Code collision with another user: retry with a new random code.
      if (!(e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002")) throw e;
    }
  }
  const fresh = await db.user.findUniqueOrThrow({ where: { id: userId }, select: { referralCode: true } });
  if (!fresh.referralCode) throw new Error("referral code generation failed");
  return fresh.referralCode;
}

export async function referralStats(userId: string) {
  const [rewardedThisMonth, totalReferrals] = await Promise.all([
    db.referral.count({ where: { referrerId: userId, status: "rewarded", createdAt: { gte: monthStartUtc() } } }),
    db.referral.count({ where: { referrerId: userId, status: { in: ["rewarded", "referrer_capped"] } } }),
  ]);
  return { rewardedThisMonth, remainingThisMonth: Math.max(0, MONTHLY_CAP - rewardedThisMonth), totalReferrals };
}

type Reject = "self" | "duplicate_email" | "unverified_email" | "ip_limit" | "ratelimit_unavailable";

async function reject(referrerId: string, refereeId: string, reason: Reject) {
  await db.referral
    .create({ data: { referrerId, refereeId, status: "rejected", rejectReason: reason } })
    .catch(() => {});
  posthog.capture({ distinctId: referrerId, event: "referral_rejected", properties: { referrer_id: referrerId, reason } });
}

// Called from NextAuth events.createUser. Never throws: signup must not depend on referrals.
export async function processNewUser(refereeId: string, code: string | undefined, ipHash: string) {
  try {
    const referee = await db.user.findUnique({ where: { id: refereeId } });
    if (!referee) return;

    // Recorded for every new user so later signups can be deduplicated against it.
    let duplicate = false;
    try {
      await db.user.update({ where: { id: refereeId }, data: { emailNormalized: normalizeEmail(referee.email) } });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === "P2002") duplicate = true;
      else throw e;
    }

    if (!code || !CODE_RE.test(code)) return;
    const referrer = await db.user.findUnique({ where: { referralCode: code }, select: { id: true } });
    if (!referrer) return;
    if (!(await referralsEnabled(referrer.id))) return;

    if (referrer.id === refereeId) return reject(referrer.id, refereeId, "self");
    if (duplicate) return reject(referrer.id, refereeId, "duplicate_email");
    if (!referee.emailVerified) return reject(referrer.id, refereeId, "unverified_email");

    try {
      const { success } = await ratelimit(5, "24 h").limit(`referral-signup:${ipHash}`);
      if (!success) return reject(referrer.id, refereeId, "ip_limit");
    } catch {
      return reject(referrer.id, refereeId, "ratelimit_unavailable");
    }

    const status = await db.$transaction(async (tx) => {
      // Lock the referrer row so concurrent signups can't both pass the monthly cap.
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${referrer.id} FOR UPDATE`;
      const used = await tx.referral.count({
        where: { referrerId: referrer.id, status: "rewarded", createdAt: { gte: monthStartUtc() } },
      });
      const capped = used >= MONTHLY_CAP;
      const referral = await tx.referral.create({
        data: { referrerId: referrer.id, refereeId, status: capped ? "referrer_capped" : "rewarded" },
      });
      const grants = [
        { userId: refereeId, role: "referee" },
        ...(capped ? [] : [{ userId: referrer.id, role: "referrer" }]),
      ];
      for (const g of grants) {
        await tx.creditLedger.create({
          data: { userId: g.userId, amountCents: REWARD_CENTS, reason: "referral", role: g.role, referralId: referral.id },
        });
        await tx.user.update({ where: { id: g.userId }, data: { credits: { increment: REWARD_CENTS } } });
      }
      return referral.status;
    });

    if (status === "rewarded") {
      posthog.capture({
        distinctId: referrer.id,
        event: "referral_rewarded",
        properties: { referrer_id: referrer.id, referee_id: refereeId, amount_cents: REWARD_CENTS },
      });
    } else {
      posthog.capture({
        distinctId: referrer.id,
        event: "referral_rejected",
        properties: { referrer_id: referrer.id, reason: "referrer_capped" },
      });
    }
  } catch (e) {
    posthog.capture({
      distinctId: refereeId,
      event: "referral_failed",
      properties: { referee_id: refereeId, error_code: e instanceof Error ? e.name : "unknown" },
    });
  }
}
