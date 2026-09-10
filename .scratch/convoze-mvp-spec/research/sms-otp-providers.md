# SMS / OTP Delivery Providers — Research Findings

Context: Convoze is a solo-developer portfolio project (Flutter mobile client + Node.js/PostgreSQL backend). Auth model is already decided: phone number + OTP. This research is to pick a delivery/verification provider. Traffic is portfolio-scale (dozens to low hundreds of OTPs/month), not production volume. Sources below are official docs/pricing/SDK pages only.

---

## 1. Twilio Verify

**Integration effort**
- Official Node.js SDK: `twilio` on npm, published and maintained by Twilio, source at `github.com/twilio/twilio-node`. Confirmed via npm registry metadata (maintainers on `@twilio.com` addresses). — https://www.npmjs.com/package/twilio
- Backend usage pattern: `client.verify.v2.services(VERIFY_SERVICE_SID).verifications.create({ to, channel: 'sms' })` to send, and `.verificationChecks.create({ to, code })` to check. — https://www.twilio.com/docs/verify/quickstarts/node-express , https://www.twilio.com/docs/verify/api
- No official Flutter/Dart SDK. Verify is REST-only; the Flutter app calls your Node backend, which calls Twilio — there is no client-side Twilio SDK involved in the OTP flow itself.

**Pricing at low volume**
- $0.05 per **successful** verification (this fee is only charged on success, not on every send/resend) + a separate per-message channel fee. For US SMS, channel fee is $0.0083/SMS in addition to the $0.05. — https://www.twilio.com/en-us/verify/pricing
- International SMS channel fees vary by destination country (linked from the same pricing page).
- No published free-tier quota for Verify itself, but Twilio offers a free trial account (no credit card required) to test the flow before paying. — https://www.twilio.com/docs/usage/trials
- Volume discounts exist but are custom/sales-negotiated, not published. — https://www.twilio.com/en-us/verify/pricing

**Delivery reliability / caveats**
- **Trial account restriction**: a Twilio trial account can only send SMS/calls to phone numbers you've explicitly verified in the console (up to 5 verified recipients), and outbound trial SMS are prefixed with "Sent from a Twilio Trial account". This restriction is lifted only after upgrading to a paid account with an approved compliance profile. This is directly relevant for a portfolio build/demo where you'd want to send to arbitrary numbers (e.g. reviewers testing the app) without upgrading. — https://support.twilio.com/hc/en-us/articles/360036052753-Twilio-Free-Trial-Limitations , https://www.twilio.com/docs/api/errors/21608
- Regional SMS pricing/deliverability varies by country/carrier (see international pricing link on the pricing page above); no specific "unsupported countries" list was found in Verify docs at time of writing.

**Where verification logic lives**
- **Server-side.** Twilio Verify itself is the OTP store: Twilio generates the code, sends it, and holds the pending verification state server-side against the Verify Service SID. Your Node backend calls `verifications.create()` to trigger a send and `verificationChecks.create()` to check the user-submitted code — Twilio's API returns `approved`/`pending` status. This means Convoze's backend does **not** need its own OTP table with expiry logic; Twilio manages code generation, expiry, and match-checking behind its API. Your backend still owns the "what happens after verification succeeds" step (issuing your own session/JWT). — https://www.twilio.com/docs/verify/api

---

## 2. Firebase Phone Auth

**Integration effort**
- Official Flutter/Dart package: `firebase_auth` on pub.dev, published by a pub.dev "verified publisher" (Firebase/Google), part of FlutterFire. Supports `verifyPhoneNumber()`. — https://pub.dev/packages/firebase_auth , https://firebase.google.com/docs/auth/flutter/phone-auth
- This is fundamentally a **client-driven** flow: the Flutter app talks directly to Firebase's Auth backend via the SDK (no OTP ever touches your Node server). On success, the SDK yields a Firebase **ID token**; your Node backend's only job is to verify that ID token (via `firebase-admin` Node SDK) and trust the phone number claim inside it — it never generates, stores, or checks an OTP code itself.
- Web platform additionally requires a reCAPTCHA widget before SMS is sent; native Android can auto-resolve the SMS via device APIs without user typing the code. — https://firebase.google.com/docs/auth/flutter/phone-auth
- Testing/emulators: phone sign-in only works on real devices and web — not on emulators/simulators — unless you configure fixed "test numbers + test codes" in the Firebase console. — https://firebase.google.com/docs/auth/flutter/phone-auth

**Pricing at low volume**
- Phone Auth is billed **per SMS sent**, and since **September 2024** Firebase requires the project to be linked to a Cloud Billing account (i.e., on the Blaze pay-as-you-go plan) to enable/use the phone-auth SMS service at all — there is no longer a way to use it purely on the free Spark plan. — https://firebase.google.com/docs/auth/faq-and-troubleshooting , https://firebase.google.com/pricing
- Actual per-SMS rates are set by the underlying Google Cloud Identity Platform pricing table and vary sharply by destination country — reported figures include ~$0.01/SMS for US/Canada up to $0.05–$0.10+ for markets like UK/Germany/India, and higher still in some regions. Check the live table for exact current rates by country. — https://cloud.google.com/identity-platform/pricing
- No published "N free SMS/month" allowance for phone auth specifically (unlike Identity Platform's separate MFA feature, which has a documented small daily free allowance for multi-factor SMS — not the same as primary phone sign-in). Confirm current numbers directly on the pricing page before committing, since this is a frequently-changing table.

**Delivery reliability / caveats**
- Firebase states phone auth is supported broadly (230+ regions/territories) but explicitly warns "not all networks reliably deliver verification messages," with typical healthy success rates cited in the 70–85% range since SMS delivery isn't guaranteed. — https://firebase.google.com/docs/auth/faq-and-troubleshooting
- A documented gap: if a user ports their phone number between carriers, SMS delivery to that number can break entirely with "no current workaround." — https://firebase.google.com/docs/auth/faq-and-troubleshooting
- Google recommends enabling App Check and an SMS Region Policy to guard against abuse/toll fraud — extra setup surface beyond the happy path. — https://firebase.google.com/docs/auth/faq-and-troubleshooting

**Where verification logic lives**
- **Client-side, by design.** The Firebase client SDK (`firebase_auth` in Flutter) drives the entire OTP challenge/response with Firebase's backend directly. The Node backend never sees the raw OTP and never stores one — it only receives and verifies a signed Firebase ID token (via `firebase-admin`) to confirm the user is who they claim to be. **This means no OTP table/store and no OTP-matching logic exists in the Node backend at all** — architecturally the opposite of what the task brief wants to demonstrate (there's no server-side OTP generation/expiry/verification code to show off).

---

## 3. MSG91

**Integration effort**
- Official Node.js SDKs exist directly under the MSG91 GitHub org: `MSG91/sendotp-node` (OTP-specific: send/retry/verify OTP) and `MSG91/MSG91-node` (general messaging API). — https://github.com/MSG91/sendotp-node , https://github.com/MSG91/MSG91-node
- On npm, the official package is `msg91` (install via `npm i msg91`), maintained under the `msg91com` npm profile. There are also several third-party/unofficial wrappers (`msg91-lib`, `msg91-api`, `msg91-v5`, `@walkover/msg91`) — these are community packages, not official. — https://www.npmjs.com/~msg91com , https://www.npmjs.com/package/msg91
- Maintenance caveat: the `sendotp-node` GitHub repo shows relatively low commit activity (around two dozen commits) and multiple open issues, suggesting it isn't heavily actively developed — worth a quick freshness check before depending on it, though MSG91's REST API can always be called directly with a plain HTTP client as a fallback.
- No official Flutter/Dart SDK — this is backend/REST-driven only, same integration shape as Twilio Verify: Flutter app → Node backend → MSG91 API.
- MSG91 provides a hosted "OTP Widget" (with optional client-side embed + captcha) as an alternative to pure backend-driven OTP, but the core send/verify API is what a Node backend would use. — https://docs.msg91.com/otp-widget/send-otp-1 , https://docs.msg91.com/otp-widget/verify-otp

**Pricing at low volume**
- No permanent free tier for OTP volume; billing is purely usage-based per OTP sent, with no monthly subscription fee for using the OTP Widget/API itself. — https://msg91.com/help/sendotp/how-to-integrate-the-new-login-with-otp-widget/msg91-otp-widget-subscription- , https://msg91.com/in/pricing/otpwidget
- US-destination SMS OTP rate quoted on MSG91's official US pricing page: **$0.0096 per OTP**. — https://msg91.com/us/pricing/otp
- Demo/trial credits are given at signup for evaluation, and MSG91 runs a separate "Startups" program offering up to 25,000 free SMS credits for 6 months for eligible startups (requires a private/company domain email, not gmail/yahoo/outlook) — not something a personal portfolio signup with a personal email would qualify for. — https://msg91.com/startups , https://knowledgebase.msg91.com/how-to-avail-msg91-start-up-offer-
- India-market pricing (MSG91's primary market) is on a separate regional pricing page and is generally cheaper than the US-quoted rate; check `msg91.com/in/pricing/otpwidget` if targeting Indian numbers specifically.

**Delivery reliability / caveats**
- MSG91 is India-headquartered and India-focused; delivery quality/regulatory requirements (e.g., DLT registration for India SMS, a known Indian telecom compliance requirement referenced by MSG91's v5 API branding) can add setup friction for Indian numbers specifically — relevant since a portfolio project may want to demo with an Indian number. No explicit "unsupported countries" list was surfaced in the pages reviewed; MSG91 markets multi-channel delivery (SMS/Voice/Email/WhatsApp) as fallback options.

**Where verification logic lives**
- **Server-side**, same architectural model as Twilio Verify: the Node backend calls MSG91's send-OTP API, and later calls MSG91's verify-OTP API with the user-submitted code — MSG91 holds the pending OTP state on their side per the OTP Widget flow. — https://docs.msg91.com/otp-widget/send-otp-1 , https://docs.msg91.com/otp-widget/verify-otp
- Like Twilio, this means MSG91 (not your Postgres/Redis) is the source of truth for OTP matching/expiry if you use their `sendOtp`/`verifyOtp` endpoints as documented — though nothing stops you from instead using MSG91 purely as an SMS *transport* (send a plain templated SMS containing an OTP you generated yourself) and doing all generation/expiry/matching in your own Postgres, which is closer to a fully "roll your own OTP logic + third-party SMS transport" architecture if that's the point you want to demonstrate.

---

## 4. AWS SNS / AWS End User Messaging SMS (formerly "Pinpoint SMS")

**Naming clarification (as of 2026)**: AWS announced in July 2024 that the SMS/MMS/push/voice messaging capabilities previously under **Amazon Pinpoint** were rebranded as **AWS End User Messaging**. The underlying API, SDK client name, and CLI commands still reference "pinpoint" internally (e.g., npm package `@aws-sdk/client-pinpoint-sms-voice-v2`), but "AWS End User Messaging SMS" is the current official product/doc name going forward, and Amazon Pinpoint (the broader campaign/analytics product) has an announced end-of-support date of October 2026. Existing Pinpoint SMS usage isn't broken by this, but for a **new** integration in 2026, AWS End User Messaging is the currently-authoritative name/entry point to build against. — https://aws.amazon.com/about-aws/whats-new/2024/07/aws-end-user-messaging , https://aws.amazon.com/blogs/messaging-and-targeting/aws-end-user-messaging-sms-and-voice-v2-api-a-migration-guide-from-v1/

**Integration effort**
- Official Node.js SDK for the current v2 SMS/voice API: `@aws-sdk/client-pinpoint-sms-voice-v2` (part of AWS SDK for JavaScript v3, `github.com/aws/aws-sdk-js-v3`). — https://www.npmjs.com/package/@aws-sdk/client-pinpoint-sms-voice-v2
- Plain Amazon SNS (a separate, simpler pub/sub-style service that can also fire one-off SMS via its `Publish` API) has its own official SDK package: `@aws-sdk/client-sns`, also under `aws-sdk-js-v3`. — https://www.npmjs.com/package/@aws-sdk/client-sns , https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/javascript_sns_code_examples.html
- No official Flutter/Dart SDK for either service — this is entirely backend-driven: Node backend uses the AWS SDK (with IAM credentials) to trigger sends; Flutter only ever talks to your own backend.

**Pricing at low volume**
- No free tier for SMS sending; strictly pay-as-you-go, with per-message price varying by destination country/region and even by carrier within a country. — https://aws.amazon.com/end-user-messaging/pricing
- **OTP-specific fee**: AWS End User Messaging charges **$0.045 per successful OTP verification**, in addition to the normal per-SMS send cost. This implies AWS also has a "Verify"-style managed OTP capability layered on top of raw SMS sending (not just raw `Publish`), conceptually similar to Twilio Verify. — https://aws.amazon.com/end-user-messaging/pricing
- Underlying US per-message SMS cost is in the roughly $0.006–$0.012/message-part range plus carrier fees depending on originator type (10DLC/toll-free/short code); exact current figures are in the downloadable pricing CSV linked from the pricing page rather than a simple flat table. — https://aws.amazon.com/end-user-messaging/pricing
- Optional "SMS Protect" fraud-filtering add-on costs $0.01/message in "monitor"/"filter" modes (no charge in "allow"/"block" modes) — an avoidable extra for a small portfolio build. — https://aws.amazon.com/end-user-messaging/pricing

**Delivery reliability / caveats**
- AWS explicitly documents that pricing (and by extension deliverability requirements like number registration) differs by destination country and even carrier within a country — there is meaningfully more setup complexity here (originator/number provisioning, e.g., 10DLC registration for US traffic) than with Twilio Verify or MSG91's higher-level OTP APIs, since AWS's raw SMS layer is closer to telecom primitives than a packaged "verify" product. — https://aws.amazon.com/end-user-messaging/pricing
- Amazon Pinpoint (the older, broader product) has an announced end-of-support date of October 2026; existing SMS functionality isn't immediately broken, but this reinforces that AWS End User Messaging (not "Pinpoint") is the name/target to build against now. — https://github.com/aws/aws-sdk-net/discussions/4245 , https://aws.amazon.com/about-aws/whats-new/2024/07/aws-end-user-messaging

**Where verification logic lives**
- **Depends which AWS building block you use**, and this is the key nuance for AWS specifically:
  - If you use plain **Amazon SNS `Publish`**, AWS only sends the SMS — SNS has no concept of "OTP" at all. Your Node backend must generate the code, store it (e.g., in Postgres with an expiry column, or Redis), and verify the submitted code itself. This is the "fully server-side, roll-your-own" model.
  - If you use **AWS End User Messaging's OTP/Verify-style capability** (the one billed at $0.045/successful verification), AWS is managing verification state similarly to Twilio Verify — you call its send API and its check/verify API, and AWS holds the pending-code state. — https://aws.amazon.com/end-user-messaging/pricing
  - Either way, verification logic is **server-side** (there is no AWS Flutter SDK participating in the flow) — the only question is whether your own Postgres/Redis is the source of truth (SNS route) or AWS's API is (End User Messaging OTP route).

---

## Comparison Table

| Provider | Node SDK | Flutter support | Low-volume cost | Verification location | Notable caveat |
|---|---|---|---|---|---|
| **Twilio Verify** | Official — `twilio` (npm) [source](https://www.npmjs.com/package/twilio) | None (REST-only; backend-driven) | $0.05/successful verification + ~$0.0083/SMS (US) — [pricing](https://www.twilio.com/en-us/verify/pricing) | Server-side, but Twilio hosts the OTP state (your backend just calls send/check APIs) | Trial accounts can only message pre-verified numbers (max 5) — [docs](https://support.twilio.com/hc/en-us/articles/360036052753-Twilio-Free-Trial-Limitations) |
| **Firebase Phone Auth** | N/A (client-driven; backend only verifies ID tokens via `firebase-admin`) | Official — `firebase_auth` (pub.dev, verified publisher) [source](https://pub.dev/packages/firebase_auth) | No free tier since Sept 2024 (requires Blaze billing); per-SMS cost varies ~$0.01–$0.10+/country — [pricing](https://cloud.google.com/identity-platform/pricing) | **Client-side** — Firebase SDK verifies the code on-device; backend only trusts the resulting ID token | Backend has no OTP table/logic at all — architecturally the weakest fit for "show off server-side OTP design" — [FAQ](https://firebase.google.com/docs/auth/faq-and-troubleshooting) |
| **MSG91** | Official — `msg91` (npm, under `msg91com`) and `MSG91/sendotp-node` (GitHub) [source](https://github.com/MSG91/sendotp-node) | None (REST-only; backend-driven, or optional hosted widget) | No free tier; **$0.0096/OTP** (US) — [pricing](https://msg91.com/us/pricing/otp) | Server-side, MSG91 hosts OTP state via their send/verify OTP API — [docs](https://docs.msg91.com/otp-widget/verify-otp) | India-focused; official SDK repo shows fairly low recent activity — worth sanity-checking before depending on it |
| **AWS SNS / End User Messaging SMS** | Official — `@aws-sdk/client-sns` and `@aws-sdk/client-pinpoint-sms-voice-v2` (both `aws-sdk-js-v3`) [source](https://www.npmjs.com/package/@aws-sdk/client-sns) | None (backend-driven only) | No free tier; **$0.045/successful OTP verification** (End User Messaging OTP) + per-SMS send cost (~$0.006–$0.012 US + carrier fees) — [pricing](https://aws.amazon.com/end-user-messaging/pricing) | **Server-side** — either fully DIY (plain SNS `Publish`, you store/check the code) or AWS-hosted state (End User Messaging OTP API) | Rebranded from "Pinpoint" in 2024; raw SNS path needs you to build OTP storage/expiry yourself; number/10DLC provisioning adds setup complexity |

## Recommendation

**Twilio Verify** is the best fit for this build. It has the cleanest, most heavily-documented official Node.js SDK of the four, a generous no-credit-card trial that's sufficient for portfolio-scale testing (once a few real numbers are verified in the trial console), and — critically for a solo dev optimizing for demonstrable backend architecture — a request/response shape (`verifications.create` → `verificationChecks.create`) that's simple enough to wrap cleanly in a Node service layer while still giving you a real third-party integration to show in interviews, unlike Firebase Phone Auth which pushes all OTP logic to the client SDK and leaves the backend with nothing more than a token-verification middleware. If the goal is instead to specifically showcase **your own** OTP generation/expiry/matching logic against Postgres (rather than delegate that state to a vendor), the better move is AWS SNS `Publish` (or MSG91 as a plain SMS transport) used purely as a dumb SMS sender, with your Node backend owning an `otp_codes` table (code hash, expiry, attempt count) and its own verification endpoint — that's more backend work to build and demo, but it's the most "architecturally honest" way to prove out server-side OTP design end-to-end. Firebase Phone Auth is the easiest to wire up but is the weakest choice here specifically because it removes the exact backend logic (OTP storage, expiry, verification) that this project wants to showcase; MSG91 is a reasonable low-cost alternative to Twilio with an equivalent server-side model, but its lighter SDK maintenance activity and India-centric focus make it the second choice rather than the primary pick.
