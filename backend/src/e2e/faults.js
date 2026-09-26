import { sendError } from '../http/errors.js';

// Fault injection for e2e tests: the next `count` calls to `method path`
// fail before reaching the real handler, with `status` and error `code`
// (503 fault_injected unless given, e.g. 502 otp_provider_unavailable to
// stand in for an SMS provider outage). The same idea extends to socket
// events (#54): the next `count` calls to a given event fail before
// reaching the real handler, acked with `{ ok: false, code }` the same way
// a real guard rejection would be, so the Outbox drainer's retry/failed
// logic can be exercised deterministically.
// Decrements `map[key]`'s `remaining`, deleting it once exhausted, and
// answers the fault (or undefined if none is pending) — the one piece the
// HTTP and socket-event injectors below share.
function consume(map, key) {
  const fault = map.get(key);
  if (!fault) return undefined;
  fault.remaining -= 1;
  if (fault.remaining === 0) map.delete(key);
  return fault;
}

export function createFaultInjector() {
  const pending = new Map();
  const pendingEvents = new Map();
  const key = (method, path) => `${method.toUpperCase()} ${path}`;

  return {
    inject(method, path, count, { status = 503, code = 'fault_injected' } = {}) {
      pending.set(key(method, path), { remaining: count, status, code });
    },
    injectEvent(event, count, { code } = {}) {
      pendingEvents.set(event, { remaining: count, code });
    },
    // Consumes and returns the injected `code` for `event`, or null if none
    // is pending.
    consumeEvent(event) {
      return consume(pendingEvents, event)?.code ?? null;
    },
    clear() {
      pending.clear();
      pendingEvents.clear();
    },
    middleware(req, res, next) {
      const k = key(req.method, req.path);
      const fault = consume(pending, k);
      if (!fault) {
        next();
        return;
      }
      sendError(res, fault.status, fault.code, `Injected failure for ${k}`);
    },
  };
}
