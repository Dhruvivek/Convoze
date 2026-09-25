// A per-sender sliding-window rate limit (ADR 0008: "~30 messages / 10s"),
// shared across every messaging action that inserts content — `message:send`
// today, `message:edit`/`reaction:toggle` in a later ticket — rather than
// one limiter per action, since the guard is stated per sender, not per
// action. In-memory only, per ADR 0008's single-backend-instance constraint.
export function createSendRateLimit({ clock, limit = 30, windowMs = 10_000 }) {
  const attemptsByUser = new Map(); // userId -> attempt timestamps, oldest first

  return {
    // Records one attempt now and reports whether it's under the limit. A
    // `false` result doesn't consume a slot, so the caller can retry later
    // without being punished twice for the same rejected attempt.
    consume(userId) {
      const now = clock.now().getTime();
      const cutoff = now - windowMs;
      const attempts = attemptsByUser.get(userId) ?? [];
      while (attempts.length > 0 && attempts[0] <= cutoff) attempts.shift();
      if (attempts.length >= limit) return false;
      attempts.push(now);
      attemptsByUser.set(userId, attempts);
      return true;
    },
  };
}
