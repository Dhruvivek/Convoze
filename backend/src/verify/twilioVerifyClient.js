import twilio from 'twilio';

// The production Verify client: Twilio Verify owns code generation, delivery
// and expiry (ADR 0003). Same interface as fakeVerifyClient.js.
export function createTwilioVerifyClient({ accountSid, authToken, verifyServiceSid }) {
  const service = twilio(accountSid, authToken).verify.v2.services(verifyServiceSid);

  return {
    async sendCode(phoneNumber) {
      await service.verifications.create({ to: phoneNumber, channel: 'sms' });
    },
    async checkCode(phoneNumber, code) {
      try {
        const check = await service.verificationChecks.create({ to: phoneNumber, code });
        return check.status === 'approved';
      } catch (err) {
        // 404: no pending verification — it expired, was already approved,
        // or ran out of attempts. To the caller that is just a wrong code.
        if (err.status === 404) return false;
        throw err;
      }
    },
  };
}
