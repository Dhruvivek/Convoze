export const RETENTION_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

// Prunes UserUpdate rows older than the 30-day retention window (ADR 0008): a
// Device that's been offline longer than that always resyncs from a REST
// snapshot instead, by design. `clock` is the injectable "now" every other
// time-dependent rule in this backend uses, so tests can control it.
export async function pruneOldUpdates(prisma, clock) {
  const cutoff = new Date(clock.now().getTime() - RETENTION_DAYS * DAY_MS);
  const { count } = await prisma.userUpdate.deleteMany({ where: { createdAt: { lt: cutoff } } });
  return count;
}

// Runs `pruneOldUpdates` on an hourly interval until `stop()`. A single
// backend instance (ADR 0008's stated constraint), so a plain interval needs
// no distributed lock.
export function startRetentionJob({ prisma, clock, intervalMs = HOUR_MS }) {
  const timer = setInterval(() => {
    pruneOldUpdates(prisma, clock).catch((err) => console.error(err));
  }, intervalMs);
  timer.unref?.();
  return { stop: () => clearInterval(timer) };
}
