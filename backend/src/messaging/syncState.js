// Resolves a connecting Device's handshake `since` against the User's
// Update log (ADR 0008). `since` must be present, no older than the oldest
// Update the log still retains, and no newer than the User's current
// `lastSeq` (a client can never legitimately be ahead of the server) —
// otherwise the Device has a gap only a REST snapshot can fill, and the
// pump starts fresh from `currentSeq` instead of trying to resume.
export async function resolveStartSeq(prisma, userId, since) {
  const [seqRow, oldest] = await Promise.all([
    prisma.userSeq.findUnique({ where: { userId } }),
    prisma.userUpdate.findFirst({
      where: { userId },
      orderBy: { seq: 'asc' },
      select: { seq: true },
    }),
  ]);
  const lastSeq = seqRow ? Number(seqRow.lastSeq) : 0;
  // Retention having pruned every one of this User's rows (a Device offline
  // past the retention window, ADR 0008) looks the same as their never
  // having had any: treat "nothing retained" as if the oldest row were just
  // past `lastSeq`, so any `since` short of `lastSeq` still reads as a gap
  // instead of being mistaken for a brand-new Device that's already caught up.
  const oldestSeq = oldest ? Number(oldest.seq) : lastSeq + 1;

  const sinceIsValid = Number.isInteger(since) && since >= 0;
  // A gap only exists once retention has pruned rows between `since` and the
  // oldest one still held — `since` sitting just below it (the ordinary
  // "resume from here" case, including a brand-new Device's `since: 0`) is
  // not a gap.
  const hasGap = since < oldestSeq - 1;
  const needsReset = !sinceIsValid || since > lastSeq || hasGap;

  return needsReset ? { startSeq: lastSeq, resetSeq: lastSeq } : { startSeq: since, resetSeq: null };
}
