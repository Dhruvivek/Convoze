// Stand-in for Twilio Verify, used by tests and e2e mode: no SMS is sent,
// and only the one fixed code is approved.
//
// Verify client interface (the real one is twilioVerifyClient.js):
//   sendCode(phoneNumber) -> Promise<void>
//   checkCode(phoneNumber, code) -> Promise<boolean>  (true = approved)
export function createFakeVerifyClient({ code }) {
  return {
    async sendCode(_phoneNumber) {},
    async checkCode(_phoneNumber, submittedCode) {
      return submittedCode === code;
    },
  };
}
