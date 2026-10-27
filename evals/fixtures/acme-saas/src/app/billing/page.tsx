import { auth } from "@/auth";
import { db } from "@/lib/db";

export default async function Billing() {
  const session = await auth();
  const user = await db.user.findUnique({
    where: { email: session?.user?.email ?? "" },
    include: { subscriptions: true },
  });

  return (
    <main>
      <h1>Billing</h1>
      <ul>
        {user.subscriptions.map((s) => (
          <li key={s.id}>
            {s.priceId}: {s.status}
          </li>
        ))}
      </ul>
    </main>
  );
}
