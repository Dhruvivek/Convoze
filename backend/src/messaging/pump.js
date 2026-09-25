import { moveDeliveryWatermarksOnAck } from './deliveryWatermark.js';
import { hydrateUpdates } from './hydrator.js';

export const DEFAULT_PUMP_BATCH_SIZE = 100;
export const DEFAULT_PUMP_ACK_TIMEOUT_MS = 15_000;

// One pump per socket (ADR 0008): the only thing that ever emits Updates.
// Drains `userId`'s Update log from `startSeq` in ack'd batches of up to
// `batchSize`, then sleeps until `wake()` is called again — by the Update
// writer's `onWake` hook once this User has a new Update, or by the caller
// right after creating the pump to run its first drain. An unacked batch
// (ack timeout) stops the pump for good: the Device's own `since` on its
// next connect is what resumes delivery, not this instance retrying.
export function createPump({
  prisma,
  socket,
  userId,
  startSeq,
  onWake,
  batchSize = DEFAULT_PUMP_BATCH_SIZE,
  ackTimeoutMs = DEFAULT_PUMP_ACK_TIMEOUT_MS,
}) {
  let lastSent = startSeq;
  let stopped = false;
  let draining = false;
  // Set when `wake()` arrives while already draining, so the write that
  // triggered it isn't missed: the drain loop's own `seq > lastSent` read
  // already ran and won't see it.
  let wakeAgain = false;

  async function drain() {
    if (draining) {
      wakeAgain = true;
      return;
    }
    draining = true;
    try {
      while (!stopped) {
        const rows = await prisma.userUpdate.findMany({
          where: { userId, seq: { gt: BigInt(lastSent) } },
          orderBy: { seq: 'asc' },
          take: batchSize,
        });
        if (rows.length === 0) {
          socket.emit('sync:caught-up', { seq: lastSent });
          return;
        }

        const { updates, users } = await hydrateUpdates(prisma, rows);
        let ackTimedOut = false;
        try {
          await socket.timeout(ackTimeoutMs).emitWithAck('sync:batch', { updates, users });
        } catch {
          ackTimedOut = true;
        }
        if (ackTimedOut) {
          stopped = true;
          return;
        }
        // Delivery watermark moves on ack (ADR 0008), ahead of the next
        // batch (or `sync:caught-up`), so a batch this drain sent is always
        // reflected in `lastDeliveredMessageId` before this pump reports
        // itself caught up. Its own try/catch, separate from the one below:
        // this is bookkeeping alongside the batch this drain already
        // delivered, not a precondition for delivering the next one, so a
        // failure here (a busy connection pool, say) shouldn't stop the
        // whole pump the way a failure reading or sending Updates does.
        if (onWake) {
          try {
            await moveDeliveryWatermarksOnAck(prisma, { userId, updates, onWake });
          } catch (err) {
            console.error(err);
          }
        }
        lastSent = Number(rows[rows.length - 1].seq);
      }
    } catch (err) {
      // A DB hiccup mid-drain shouldn't take the socket layer down with it;
      // the Device's next connect (or this User's next Update) tries again.
      console.error(err);
      stopped = true;
    } finally {
      draining = false;
      if (wakeAgain && !stopped) {
        wakeAgain = false;
        drain();
      }
    }
  }

  return {
    // Starts (or resumes) draining; safe to call any number of times,
    // including while already draining.
    wake() {
      if (!stopped) drain();
    },
    stop() {
      stopped = true;
    },
  };
}
