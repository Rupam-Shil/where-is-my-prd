import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

export const ratelimit = (requests: number, window: `${number} ${"s" | "m" | "h"}`) =>
  new Ratelimit({ redis: Redis.fromEnv(), limiter: Ratelimit.slidingWindow(requests, window) });
