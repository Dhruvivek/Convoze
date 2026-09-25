// In-process subscription point that fires with `{ sessionId, userId }`
// whenever a Session is revoked, for whatever reason. Realtime transport
// (ADR 0005) subscribes to force-disconnect that Session's sockets.
//
// A subscriber that fails is logged, never allowed to fail the revocation.
export function createSessionRevokedHook() {
  const subscribers = new Set();

  return {
    // Returns a function that unsubscribes.
    subscribe(subscriber) {
      subscribers.add(subscriber);
      return () => subscribers.delete(subscriber);
    },
    fire(event) {
      for (const subscriber of subscribers) {
        try {
          Promise.resolve(subscriber(event)).catch(logSubscriberError);
        } catch (err) {
          logSubscriberError(err);
        }
      }
    },
  };
}

function logSubscriberError(err) {
  console.error('A session-revoked subscriber failed:', err);
}
