import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { posthog } from "@/lib/analytics";
import { ratelimit } from "@/lib/ratelimit";
import { referralsEnabled } from "@/lib/flags";
import { CODE_RE, hashIp } from "@/lib/referral";

const THIRTY_DAYS = 60 * 60 * 24 * 30;

export async function GET(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";

  try {
    const { success, reset } = await ratelimit(30, "1 m").limit(`referral-link:${hashIp(ip)}`);
    if (!success) {
      const retry = Math.max(1, Math.ceil((reset - Date.now()) / 1000));
      return new NextResponse("Too many requests", { status: 429, headers: { "Retry-After": String(retry) } });
    }
  } catch {
    // Rate limiter unavailable: continue; the signup-side limit still gates rewards.
  }

  if (!CODE_RE.test(code)) return new NextResponse("Not found", { status: 404 });
  const referrer = await db.user.findUnique({ where: { referralCode: code }, select: { id: true } });
  if (!referrer) return new NextResponse("Not found", { status: 404 });

  const res = NextResponse.redirect(new URL("/api/auth/signin", req.url));
  if (!(await referralsEnabled(referrer.id))) return res;

  posthog.capture({ distinctId: referrer.id, event: "referral_link_viewed", properties: { referrer_id: referrer.id } });
  res.cookies.set("ref", code, { httpOnly: true, secure: true, sameSite: "lax", maxAge: THIRTY_DAYS, path: "/" });
  posthog.capture({ distinctId: referrer.id, event: "referral_attributed", properties: { referrer_id: referrer.id } });
  return res;
}
