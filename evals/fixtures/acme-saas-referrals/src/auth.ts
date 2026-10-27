import NextAuth from "next-auth";
import Google from "next-auth/providers/google";
import { PrismaAdapter } from "@auth/prisma-adapter";
import { cookies, headers } from "next/headers";
import { db } from "@/lib/db";
import { hashIp, processNewUser } from "@/lib/referral";

export const { handlers, auth, signIn, signOut } = NextAuth({
  adapter: PrismaAdapter(db),
  providers: [Google],
  session: { strategy: "database" },
  callbacks: {
    session({ session, user }) {
      session.user.id = user.id;
      return session;
    },
  },
  events: {
    // Only fires for brand-new users, so existing users clicking a link never earn a reward.
    async createUser({ user }) {
      if (!user.id) return;
      const jar = await cookies();
      const h = await headers();
      const ip = h.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
      await processNewUser(user.id, jar.get("ref")?.value, hashIp(ip));
    },
  },
});
