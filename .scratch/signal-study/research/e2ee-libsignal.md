# Signal E2EE and libsignal fit for Convoze (Flutter + Node)

Issue: #11 (part of map #10, the Signal study). Researched 2026-09-17 against primary sources only (signal.org specs/blog, github.com/signalapp, pub.dev and the npm registry). Signal code is AGPLv3. This note describes how it works and does not reproduce any of it.

---

## 1. How the protocol works (explained for a solo developer)

### 1.1 Keys each device holds
- **Identity key (IK):** a long-term key pair for each install. **Signed prekey (SPK):** a medium-term key pair, signed by the IK and rotated from time to time. **One-time prekeys (OPK):** a batch of key pairs, each used once. PQXDH adds a **signed last-resort PQ (Kyber/ML-KEM) prekey** and **signed one-time PQ prekeys**. Source: PQXDH spec, Rev. 3 (updated 2024-01-23), https://signal.org/docs/specifications/pqxdh/
- The Rust implementation lives in `rust/protocol/src/{identity_key,pqxdh,kem,session}.rs`: https://github.com/signalapp/libsignal/tree/main/rust/protocol/src

### 1.2 Session setup (PQXDH, which replaced X3DH)
1. Bob uploads his IK, SPK plus signature, PQ prekeys and a batch of OPKs to the server.
2. Alice fetches a **prekey bundle** for Bob. The server hands out one OPK and one PQ one-time prekey (or the last-resort key) and **deletes the one-time keys once it has given them out**.
3. Alice does 3–4 DH operations plus one KEM encapsulation, runs them through a KDF to get the shared secret SK, and sends an initial message. That message carries her IK, her ephemeral key, the KEM ciphertext, the IDs of the prekeys she used, and the first ciphertext.
4. Bob repeats the same steps and gets the same SK. This works **asynchronously**, so Bob can be offline.
Source: https://signal.org/docs/specifications/pqxdh/

**Caveats stated in the spec:** identity authentication is only as good as users comparing fingerprints out of band. Without that check, a malicious server can impersonate Bob. If no one-time keys are left, replay becomes possible. Forward secrecy after a server compromise depends on how often the SPK rotates. Source: same PQXDH page.

### 1.3 Ongoing messages (Double Ratchet, now the "Triple Ratchet")
- **Symmetric ratchet:** each message key comes from a chain key through a KDF and is deleted after use, which gives **forward secrecy**. **DH ratchet:** each reply carries a new DH public key, and the new DH output starts fresh chains, which gives **post-compromise security**. Out-of-order messages are handled by storing skipped message keys, capped by `MAX_SKIP`. Source: Double Ratchet spec, Rev. 4 (2025-11-04), https://signal.org/docs/specifications/doubleratchet/
- Since October 2025 Signal also mixes in **SPQR** (the Sparse Post-Quantum Ratchet), which makes the combination the "Triple Ratchet". It falls back when talking to older clients. Sources: https://signal.org/blog/spqr/ and `rust/protocol/src/triple_ratchet.rs` (https://github.com/signalapp/libsignal/blob/main/rust/protocol/src/triple_ratchet.rs)

### 1.4 Safety numbers
- A safety number is per conversation: two 30-digit fingerprints, sorted and concatenated, each built from an identity key plus the user's identifier (the phone number, in the 2016 design). It can be compared by reading the digits or scanning a QR code. It **changes when a user reinstalls or gets a new phone**, which is when the "safety number changed" warning appears. Source: https://signal.org/blog/safety-number-updates/ (2016-11-17). Implementation: `rust/protocol/src/fingerprint.rs`.

### 1.5 Groups
- **Signal's original approach (2014):** there is no group key. A group message is sent as N separate pairwise-encrypted messages, and the server does not know groups exist. One optimization encrypts the body once with a random key and fans out only that key pairwise. Source: https://signal.org/blog/private-groups/
- **Sender Keys (current):** each sender has a per-group sender chain key plus a signing key. The sender distributes a `SenderKeyDistributionMessage` to each member over their existing 1:1 sessions. After that, each group message is encrypted **once** with AES-256-CBC under a key derived from the chain, then signed. The chain moves forward per message. There is no DH ratchet per message, so post-compromise security is weaker than in 1:1 chats, and keys must be rotated when membership changes. Source: `group_encrypt` / `create_sender_key_distribution_message` in https://github.com/signalapp/libsignal/blob/main/rust/protocol/src/group_cipher.rs and `sender_keys.rs`.
- **Groups v2:** group state (members, title, avatar) is stored on the server encrypted under a GroupMasterKey. Members prove their rights with zero-knowledge credentials (zkgroup), so the server cannot see who is in a group. Source: https://signal.org/blog/signal-private-group-system/ (2019-12-09). This is far beyond what a portfolio app needs.

### 1.6 Media
- Attachments are encrypted on the client with a random key per attachment. The key is AES-CBC + HMAC-SHA256 key material. The encrypted blob is uploaded, and the key and digest travel inside the E2EE message. Source: `AttachmentCipherOutputStream.kt` in Signal-Android, https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/java/org/whispersystems/signalservice/api/crypto/AttachmentCipherOutputStream.kt

## 2. What the server stores and serves, and what it can no longer see

**Stores and serves:**
- Public identity keys, signed prekeys, a pool of one-time EC and PQ prekeys, and per-device prekey counts so clients know when to top up. Signal-Server `KeysController` (`/v2/keys`): GET prekey count, PUT upload new prekeys, POST `/check`, and GET `/{identifier}/{device_id}`, which "Retrieves the public identity key and available device prekeys". Source: https://github.com/signalapp/Signal-Server/blob/main/service/src/main/java/org/whispersystems/textsecuregcm/controllers/KeysController.java
- Opaque ciphertext envelopes queued for each device (`/v1/messages/{destination}`, plus `/multi_recipient` for sealed-sender fan-out). Source: https://github.com/signalapp/Signal-Server/blob/main/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java
- Encrypted attachment blobs (`AttachmentControllerV4`, same controllers directory).

**Can no longer see:** message content, attachment content, reactions, edits, deletes and receipts. Signal sends all of these as encrypted messages, so the server cannot tell them apart from text.

**Sealed sender (short version):** the sender's identity goes inside the envelope, along with a short-lived server-issued sender certificate (identifier, identity key, expiry). The server checks a **delivery token** derived from the recipient's profile key to limit abuse. The server still learns the recipient, the timing and the IP address. When a user blocks someone, Signal rotates the profile key. Source: https://signal.org/blog/sealed-sender/ (2018-10-29). Implementation: `rust/protocol/src/sealed_sender.rs`.

## 3. Library options

| Route | Status | License | Notes |
|---|---|---|---|
| **libsignal** (Rust core; Java, Swift, TypeScript bindings) | Very active. Latest release **v0.102.3, 2026-09-15** (https://github.com/signalapp/libsignal/releases) | **AGPL-3.0-only** | README: *"Use outside of Signal is unsupported… All APIs and implementations are subject to change without notice."* https://github.com/signalapp/libsignal. It contains `rust/bridge/{ffi,jni,node}`. The C FFI bridge exists for Swift, but **there is no Dart binding**. |
| **@signalapp/libsignal-client** (npm) | 0.102.3, published 2026-09-15 (https://registry.npmjs.org/@signalapp/libsignal-client) | AGPL-3.0-only | This is a Node/Electron binding. It would run on the Convoze **server**, which in an E2EE design never encrypts anything, so it does not help the Flutter client. |
| **libsignal_protocol_dart** (pub.dev, from Mixin) | 0.8.2, published 2026-06-20. Verified publisher mixin.dev. About 175 GitHub stars. Commits in June 2026 (https://pub.dev/packages/libsignal_protocol_dart, https://github.com/MixinNetwork/libsignal_protocol_dart) | **GPL-3.0** | A pure-Dart port of the older Java protocol library: **X3DH + Double Ratchet + Sender Keys** (`lib/src/groups`), plus fingerprints. **No PQXDH, Kyber or SPQR** (its README links only the X3DH spec, and a code search for "kyber" returns 0 hits). No published audit. It runs on all Flutter platforms. |
| DIY `dart:ffi` against libsignal's C FFI bridge | Nobody maintains this, and Signal explicitly doesn't support outside use | AGPL | You would have to cross-compile Rust for Android/iOS and track breaking changes yourself. This is a lot of risk for a solo build. |
| Platform channels (Java libsignal on Android, Swift on iOS) | Possible | AGPL | You would write and maintain two native bridges plus the Dart glue. Heavy. |

**License consequence:** Convoze is **MIT** (the `LICENSE` file in the repo). Linking either GPL-3.0 (Dart port) or AGPL-3.0 (libsignal) code into the app makes the distributed app a combined work under those copyleft terms. Before adopting either, you would need to relicense or accept GPL/AGPL. (This is a general reading of the license terms, not legal advice.)

## 4. Consequences for `docs/features.md`

| Feature | Under E2EE |
|---|---|
| 1 Auth (phone+OTP) | Unchanged, but registration must also generate the IK and prekeys and upload them. Reinstalling changes the identity key, so you need a "safety number changed" UX (§1.4). |
| 2/3 Messaging + persistence | The server stores only ciphertext. **Chat history lives on the device**, so a new device or reinstall sees **no history** unless you build encrypted backups. Multi-device means one session per device. |
| 4/5 Presence, typing | Can stay server-visible metadata (a simple choice). Signal encrypts typing indicators, but that is optional here. |
| 6 Read receipts | Either keep them as server-side status fields (this leaks metadata but is simple) or send them as encrypted control messages like Signal does. |
| 8 Groups | Needs Sender Keys and key rotation on membership change, or N-way pairwise fan-out. The server can still hold membership in plaintext, since Groups v2 privacy is not required. |
| 9 Media | Encrypt on the client with a per-file key (§1.6). **The server cannot validate file type or size by content** (features.md asks for server-side validation), and it cannot make thumbnails. Only the size of the encrypted blob can be checked. |
| 10 Edit/delete | Becomes encrypted control messages the receiving client applies. "Delete for everyone" is best effort, and the server can only enforce "sender only" from envelope metadata. |
| 11 Reactions | Same as edit/delete: encrypted control messages. A `Reaction` table on the server either can't exist or is metadata only. |
| 13 **Search** | **Server-side message search (SQL `LIKE`) is impossible.** It has to be a local on-device index (e.g. SQLite FTS). User search still works. |
| 14 Pagination | History pagination becomes local DB pagination. The server only drains undelivered queues. |
| 15 Rate limiting | Still works on envelope counts and sizes, but content-based spam filtering does not. |
| 16 Block/report | Blocking still works (the server refuses delivery, or the client drops messages). **A report can't include content the server can read** unless the reporter voluntarily re-uploads the plaintext. Signal's own report endpoint takes only the sender plus the message GUID and an optional token: `POST /v1/messages/report/{source}/{messageGuid}` in MessageController (link in §2). |

## 5. Effort and risk (rough, for a solo portfolio build)

- **Full Signal parity** (PQXDH, Triple Ratchet, Sender Keys, sealed sender, multi-device, encrypted backups): **not feasible**. No supported Dart library exists, the licensing conflicts, and it is months of security-sensitive work.
- **1:1-only E2EE with `libsignal_protocol_dart`** (X3DH + Double Ratchet, one device per user): about **1–2 extra weeks** on top of the 7-day plan. Work involved: persistent Dart implementations of the 4 stores (identity, prekey, signed prekey, session) in secure local storage; a Node prekey API (upload, count, fetch bundle with atomic one-time key removal in Postgres); an opaque-envelope message path; local history, search and reactions; a safety-number screen; and handling for session resets and reinstalls. Risks: GPL-3.0 conflicts with MIT; it is classical rather than post-quantum; there is no audit; one developer maintains a crypto port that lags Signal; and bugs fail silently (messages that can't be decrypted).
- **Smaller alternative, "E2EE-lite" demo:** keep plaintext server features and add an **opt-in "secret chat" mode** for 1:1 only (the model Telegram uses). This keeps the whole features.md list working for normal chats, confines the E2EE constraints to one screen, and still demonstrates prekeys, ratcheting and safety numbers in interviews.
- **Rolling your own crypto** with `cryptography`-style primitives: **no**. Every subtle property in §1 (one-time prekey deletion, MAX_SKIP, signature checks, KEM binding) is easy to get wrong.

---

## Summary and recommendation: E2EE go/no-go and scope

**Answer: no-go on E2EE for the MVP. Build a server-trusted design now and leave a clean seam for a later, scoped, 1:1-only "secret chat" milestone.**

Reasons:
1. **No supported Flutter route.** libsignal (the only up-to-date implementation, with PQXDH and SPQR) ships Java, Swift and TypeScript bindings only, and states that use outside Signal is unsupported with no API stability. The Dart option (`libsignal_protocol_dart` 0.8.2) is maintained but classical-only (X3DH) and unaudited.
2. **License conflict.** Both options are copyleft (AGPL-3.0 / GPL-3.0), while Convoze is MIT.
3. **Feature conflict.** E2EE breaks or reshapes about half of features.md: server search, server-side media validation, content reporting, server-stored reactions/edits/read state, and history on a new device. The 7-day plan cannot absorb that.

**Scope if/when revisited (post-MVP):**
- 1:1 only, single device per user, as an opt-in "secret chat". Use `libsignal_protocol_dart` (after accepting GPL or picking a license strategy) on the client, and a Node `/keys` API modeled on Signal-Server's shape: identity key + signed prekey + one-time prekey pool, count endpoint, fetch-bundle with atomic OPK consumption.
- In secret chats: text and media encrypted client-side, and reactions/edits/deletes as encrypted control messages. Local-only search and history. Presence, typing and receipts stay server metadata. Reporting is voluntary plaintext forwarding.
- Out of scope: Sender Keys groups, sealed sender, Groups v2 zk credentials, PQ, multi-device, and encrypted backups.

**Do now so it stays possible:** keep the message `content` field opaque to server logic where you can (no server features that *require* reading content beyond search/moderation), and treat `type` as extensible, so a future `ciphertext` message type fits.
