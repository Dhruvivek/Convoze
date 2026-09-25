import { sendError } from '../http/errors.js';

// Fault injection for e2e tests: the next `count` calls to `method path`
// fail with 503 before reaching the real handler.
export function createFaultInjector() {
  const pending = new Map();
  const key = (method, path) => `${method.toUpperCase()} ${path}`;

  return {
    inject(method, path, count) {
      pending.set(key(method, path), count);
    },
    clear() {
      pending.clear();
    },
    middleware(req, res, next) {
      const k = key(req.method, req.path);
      const remaining = pending.get(k);
      if (!remaining) {
        next();
        return;
      }
      if (remaining === 1) pending.delete(k);
      else pending.set(k, remaining - 1);
      sendError(res, 503, 'fault_injected', `Injected failure for ${k}`);
    },
  };
}
