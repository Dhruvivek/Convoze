// The only source of "now" for time-dependent rules, so tests can control it.
export const systemClock = {
  now: () => new Date(),
};
