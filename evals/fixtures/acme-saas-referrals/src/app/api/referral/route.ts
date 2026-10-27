import { NextResponse } from "next/server";
import { auth } from "@/auth";
import { referralsEnabled } from "@/lib/flags";
import { getOrCreateCode, referralStats } from "@/lib/referral";

export async function GET() {
  const session = await auth();
  const userId = session?.user?.id;
  if (!userId) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  if (!(await referralsEnabled(userId))) return NextResponse.json({ error: "disabled" }, { status: 404 });

  const code = await getOrCreateCode(userId);
  const base = process.env.NEXT_PUBLIC_APP_URL ?? process.env.AUTH_URL ?? "";
  return NextResponse.json({ code, link: `${base}/r/${code}`, ...(await referralStats(userId)) });
}
