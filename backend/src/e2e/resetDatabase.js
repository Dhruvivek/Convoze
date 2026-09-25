// Empties every application table (everything except Prisma's migration
// history), so tables added by later migrations are covered automatically.
export async function resetDatabase(prisma) {
  const rows = await prisma.$queryRaw`
    SELECT tablename FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'
  `;
  if (rows.length === 0) return;

  const tables = rows.map(({ tablename }) => `"public"."${tablename}"`).join(', ');
  // TRUNCATE takes an ACCESS EXCLUSIVE lock, which can deadlock (Postgres
  // 40P01) against a just-finishing request's own transaction (a pump's
  // post-ack watermark move, say) still holding row locks on one of these
  // tables. Postgres always resolves a deadlock by aborting one side, so a
  // single retry is the standard, safe response — not a symptom to mask.
  try {
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${tables} RESTART IDENTITY CASCADE`);
  } catch (err) {
    if (err.code !== 'P2010' || err.meta?.driverAdapterError?.cause?.originalCode !== '40P01') throw err;
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${tables} RESTART IDENTITY CASCADE`);
  }
}
