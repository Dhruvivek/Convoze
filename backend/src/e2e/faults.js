import { sendError } from '../http/errors.js';

// Fault injection for e2e tests: the next `count` calls to `method path`
// fail before reaching the real handler, with `status` and error `code`
// (503 fault_injected unless given, e.g. 502 otp_provider_unavailable to
// stand in for an SMS provider outage).
export function createFaultInjector() {
  const pending = new Map();
  const key = (method, path) => `${method.toUpperCase()} ${path}`;

  return {
    inject(method, path, count, { status = 503, code = 'fault_injected' } = {}) {
      pending.set(key(method, path), { remaining: count, status, code });
    },
    clear() {
      pending.clear();
    },
    middleware(req, res, next) {
      const k = key(req.method, req.path);
      const fault = pending.get(k);
      if (!fault) {
        next();
        return;
      }
      fault.remaining -= 1;
      if (fault.remaining === 0) pending.delete(k);
      sendError(res, fault.status, fault.code, `Injected failure for ${k}`);
    },
  };
}
