// Every code request costs real SMS money, so each phone number gets at most
// MAX_REQUESTS codes in any sliding WINDOW_MS, counted from otp_requests
// (ADR 0003).
export const MAX_REQUESTS = 3;
export const WINDOW_MS = 15 * 60 * 1000;

// Records a request before its code is sent, then counts. Checking first and
// recording after the send would let concurrent requests all see room under
// the limit; this way they can only ever reject each other, never overshoot.
// Returns the reserved request's id, or null (with nothing recorded) when
// the number is over its limit.
export async function reserveOtpRequest(prisma, phoneNumber, now) {
  const { id } = await prisma.otpRequest.create({ data: { phoneNumber, requestedAt: now } });
  const inWindow = await prisma.otpRequest.count({
    where: { phoneNumber, requestedAt: { gt: new Date(now.getTime() - WINDOW_MS) } },
  });
  if (inWindow <= MAX_REQUESTS) return id;
  await releaseOtpRequest(prisma, id);
  return null;
}

// Un-records a reserved request whose code was never sent, so it doesn't
// count against the limit.
export async function releaseOtpRequest(prisma, id) {
  await prisma.otpRequest.delete({ where: { id } });
}
