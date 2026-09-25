// Controllable clock for tests: time only moves when a test moves it.
export function createFakeClock(start = new Date('2026-01-01T00:00:00.000Z')) {
  let current = new Date(start);
  return {
    now: () => new Date(current),
    advance(ms) {
      current = new Date(current.getTime() + ms);
    },
    set(date) {
      current = new Date(date);
    },
  };
}
