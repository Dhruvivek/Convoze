# Messenger architectures: Signal, Element/Matrix, SimpleX, Telegram, WhatsApp

**Purpose:** find out how five production messengers handle identity, delivery, sync, encryption, media, push and ephemeral signals, so that Convoze ([`docs/features.md`](../features.md), [ADR 0001](../adr/0001-flutter-client-architecture.md)) can copy what fits a Node/Express + Postgres + Socket.IO backend and a Flutter/Riverpod client.

**Research date:** 2026-09-17.

**Sources:** first-party only. That means specs, whitepapers, official engineering blogs, official help pages and the source repos.
- **Signal-Server:** pinned at commit [`b30fc7a`](https://github.com/signalapp/Signal-Server/tree/b30fc7aa8bc825025e51400751feac4e65f15d13).
- **simplexmq / simplex-chat:** default branch `stable`, read at `27a3738` and `4df04bd`.
- **Matrix:** spec v1.19 ([changelog](https://github.com/matrix-org/matrix-spec/blob/main/content/changelog/v1.19.md)) and Synapse 1.161.0.
- **WhatsApp:** Encryption Overview whitepaper v9, dated 2026-02-25 ([PDF](https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf)).

**Labels used below:**
- **[inferred]** is my reading of the sources, not something they say outright.
- **[unverified]** means I found no first-party source.
- **[3P]** means only a third party has reported it.
- Telegram's and WhatsApp's servers are closed source, so everything said about them describes documented behaviour, not their code.

For readability, Signal-Server source links use the short form `SS:/path`, which expands to `https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/path`. All links are written out in full.

---

## Contents

1. [Comparison table](#1-comparison-table)
2. [Signal](#2-signal)
3. [Element / Matrix](#3-element--matrix)
4. [SimpleX Chat](#4-simplex-chat)
5. [Telegram](#5-telegram)
6. [WhatsApp](#6-whatsapp)
7. [Cross-cutting patterns](#7-cross-cutting-patterns)
8. [Lessons for Convoze](#8-lessons-for-convoze)

---

## 1. Comparison table

| Dimension | Signal | Element / Matrix | SimpleX Chat | Telegram | WhatsApp |
|---|---|---|---|---|---|
| Topology | Centralized | Federated homeservers | Relays with no user IDs; unidirectional queues | Centralized, multi-DC cloud | Centralized |
| Identity | Phone number (required), ACI/PNI UUIDs, optional usernames | `@user:server` MXID + device IDs | None; pairwise queue IDs per contact | Phone number + optional username | Phone number; usernames announced (reservation phase) |
| Server stack | Java/Dropwizard; Redis cluster cache; DynamoDB; FoundationDB (being introduced) | Python/Twisted Synapse; Postgres; Redis replication between workers | Haskell SMP/XFTP routers; in-memory + journal, or Postgres | Closed (C++ TDLib is the client) | Erlang/FreeBSD, Mnesia (per 2012/2014 talks) |
| Server stores messages | Encrypted envelopes per device until acked (TTL 30d in sample config) | All events, permanently, in the room DAG | Encrypted until ACK (default expiry 21d) | All cloud messages, permanently (server-side encrypted at rest) | Encrypted until delivered, max 30 days |
| Realtime transport | Authenticated WebSocket; server pushes `PUT /api/v1/message`, client acks | HTTP long-poll `/sync` (sliding sync in Element X) | TLS/TCP, fixed 16 KB blocks, `SUB`/`MSG`/`ACK` | MTProto over TCP/WebSocket/HTTP long-poll | Noise Pipes over a persistent connection, XMPP-derived stanzas |
| Catch-up / sync | Drain the per-device queue, then `queue/empty` | `since=next_batch` token; `limited` + `prev_batch` gaps | Queue drain one message at a time | `pts`/`qts`/`seq` + `updates.getDifference` | Offline queue drain; app-state sync by versioned patches |
| Idempotency key | Client timestamp + server GUID; acks by GUID | Per-device `txnId` in `PUT .../send/{type}/{txnId}` | `msgId` on ACK; agent seq ID + previous hash | `random_id` (dedup kept forever) + transport `msg_id` | [unverified] |
| E2EE 1:1 | Signal Protocol (PQXDH + Double Ratchet + SPQR "Triple Ratchet") | Olm (vodozemac) | Double ratchet + sntrup761 KEM, plus per-queue NaCl layers | **None** in cloud chats; opt-in secret chats (1:1, single device) | Signal Protocol |
| E2EE groups | Sender Keys + server-side encrypted group state (zkgroup) | Megolm; MLS still in MSC stage | Pairwise with every member (O(n)); channels via relays (content visible to relays) | None (groups up to 200k, channels unlimited) | Sender Keys, reset when a member leaves |
| Multi-device | Linked devices with their own keys; encrypted history archive at link time | Every device is an Olm identity; key backup/SSSS | Desktop remote-controls the phone (XRCP) | Every device is a session on the same cloud | Up to 4 companions with their own keys; signed device list; client fanout; syncd |
| Media | Encrypted blob via resumable upload form to CDN2/CDN3 | `mxc://` content repo; client-side AES-CTR for E2EE | XFTP: chunked, encrypted, multi-relay | Parts to DC; CDN DCs hold encrypted copies of popular media | Encrypted blob store; key + hash in message |
| Push | Content-free "wake up" (FCM data / APNs mutable-content) | Server push rules → Sygnal → FCM/APNs; `event_id_only` | APNs via NTF server, encrypted metadata; Android has no FCM | FCM/APNs with preview text (optionally MTProto-encrypted payload) | Wake then fetch; payload details [unverified] |
| Typing / receipts | Encrypted `TypingMessage`/`ReceiptMessage`; typing is ephemeral (online-only) | EDUs (server-visible, not in DAG) | No typing or presence; delivery receipts inside the agent protocol | Server-side: `setTyping` (6s TTL); read watermark `max_id` | Receipts/typing exist; E2EE status [unverified] |
| Server search | No | Not for E2EE rooms | No | Yes (`messages.search`) | No |
| Contact discovery | SGX enclave (CDSI) | Identity server, hashed 3PID + pepper | None (links/QR) | Address book upload | Address book upload (non-users stored hashed) |

---

## 2. Signal

### 2.1 Topology, identity, metadata
- **Centralized service.** A phone number is required to sign up. Usernames exist so you can reach someone without sharing a number, and a "Nobody" setting keeps your number hidden from people who don't already have it ([Signal blog: usernames](https://signal.org/blog/phone-number-privacy-usernames/)).
- **Two service IDs per account.** The envelope carries `source_service_id` and `destination_service_id`. These are a 16-byte UUID for the ACI, or a prefixed UUID for the PNI, the phone-number identity ([TextSecure.proto](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/proto/TextSecure.proto)).
- **Sealed sender** hides the sender from the server. The client includes a short-lived sender certificate inside the encrypted payload. For abuse control, sending sealed-sender messages needs a delivery token derived from the recipient's profile key, so in practice only contacts can do it ([Signal blog: sealed sender](https://signal.org/blog/sealed-sender/)).
  - This is why `SpamChecker` takes "the sender of the message, could be empty if this as message sent with sealed sender" (SS:`spam/SpamChecker.java`, https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/spam/SpamChecker.java).

### 2.2 Server architecture
- **Stack.** Java with Dropwizard (`dropwizard-core` in the [pom](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/pom.xml)). The README says the project "uses FoundationDB and requires the FoundationDB client library" ([README](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/README.md)).
- **Storage.** DynamoDB tables for accounts, keys, profiles and messages. The sample config gives `messages` a 30-day expiry ([sample.yml](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/config/sample.yml)).
  - A newer `storage/foundationdb/FoundationDbMessageStore.java` sits alongside `MirroringMessageStream.java` ([dir](https://github.com/signalapp/Signal-Server/tree/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/foundationdb)). **[inferred]** Message storage is being moved to FoundationDB, with writes mirrored during the switch.
- **Message delivery path.** `MessageController` exposes `PUT /v1/messages/{destination}` and `PUT /v1/messages/multi_recipient` ([MessageController.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java)).
  - `MessageSender` handles three kinds of message: "normal user-to-user messages, ephemeral ('online') messages like typing indicators, or delivery receipts".
  - If the device isn't connected, it sends a push notification. Messages flagged online-only are dropped instead ([MessageSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java)).
- **One queue per device, in Redis.** `MessagesCache` is "a low-latency holding area for new messages" ([MessagesCache.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java)). Its structure:
  - A Redis sorted set per device queue, scored by a queue-local incrementing message ID.
  - A metadata hash that maps each message GUID to that ID, so a message can be removed by GUID.
  - Lua scripts that make insert, get and remove atomic.
  - Multi-recipient messages store one shared payload plus a per-recipient "view". Each view is removed idempotently once delivered.
- **Persistence behind the cache.** `MessagePersister` moves messages that sit in Redis longer than `persistDelay` into long-term storage. The sample config has `persistDelayMinutes: 1` ([MessagePersister.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagePersister.java), [sample.yml](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/config/sample.yml)).
  - DynamoDB rows are partitioned by destination account and device, sorted by `(serverTimestamp, messageUuid)`, and carry a TTL attribute ([MessagesDynamoDb.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesDynamoDb.java)).
- **WebSocket delivery with acks.** On connect, the server streams queued envelopes to the client as `PUT /api/v1/message` requests. A successful client response triggers `acknowledgeMessage(serverGuid, serverTimestamp)`, which deletes the message. When the queue is drained, the server sends `PUT /api/v1/queue/empty` ([WebSocketConnection.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java)).
  - This is at-least-once delivery. The client dedups on its side.
- **The envelope is almost opaque.** Its fields are `type`, `source_device`, `client_timestamp`, encrypted `content`, `server_timestamp`, `ephemeral` ("should not be persisted if the recipient is offline"), `urgent`, `story`, `server_guid` and service IDs ([TextSecure.proto](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/proto/TextSecure.proto)).
- **Pluggable spam filtering.** Spam filters load dynamically through `ServiceLoader` ([SpamFilter.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/spam/SpamFilter.java)). **[inferred]** Signal's production rules are not in the public repo.
  - `POST /v1/messages/report/{source}/{messageGuid}` lets a recipient report a sender ([MessageController.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java)).

### 2.3 Registration (phone + OTP)
- **Verification is a session, not a single call.** `POST /v1/verification/session` starts it. The response says what else the server wants (a push challenge or captcha). The client supplies those with `PATCH /session/{id}`, and may only call `POST /session/{id}/code` (SMS or voice) once `allowedToRequestCode` is true.
  - Rate limiting returns 429 with a retry time, and the caller may have to switch transport ([VerificationController.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/VerificationController.java)).
- **Fraud checks are pluggable.** Hooks include `RegistrationFraudChecker` and `RegistrationRecoveryChecker` ([spam/](https://github.com/signalapp/Signal-Server/tree/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/spam)).
- **The code itself goes through a separate registration service** reached over gRPC (`RegistrationServiceClient`) ([registration/](https://github.com/signalapp/Signal-Server/tree/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/registration)).

### 2.4 Client architecture
- **Crypto lives in one Rust library, libsignal,** shared by all clients. Its crates include `libsignal-protocol`, `signal-crypto`, `zkgroup`, `zkcredential`, `attest` (SGX/HSM attestation), `usernames`, `account-keys`, `device-transfer` and `media`, with Java/Android, Swift and TypeScript bindings ([libsignal README](https://github.com/signalapp/libsignal/blob/main/README.md)). The UI apps are still native: Kotlin/Java, Swift, and Electron/TypeScript.
- **Local storage (Android) is SQLCipher.** `SignalDatabase.kt` imports `net.zetetic.database.sqlcipher.SQLiteOpenHelper` ([SignalDatabase.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/SignalDatabase.kt)).
- **Receive pipeline on Android.** `IncomingMessageObserver` → `MessageDecryptor` → `MessageContentProcessor`, which dispatches to `DataMessageProcessor`, `ReceiptMessageProcessor`, `SyncMessageProcessor`, `EditMessageProcessor` and others. `WebSocketDrainer` drains the queue ([messages/](https://github.com/signalapp/Signal-Android/tree/main/app/src/main/java/org/thoughtcrime/securesms/messages)).
- **Everything semantic is inside the encrypted `Content`.** That includes `DataMessage`, `SyncMessage` (copies to your own devices), `ReceiptMessage` (DELIVERY/READ/VIEWED, identified by the original **timestamps**), `TypingMessage` (STARTED/STOPPED + optional groupId), `EditMessage` and the `senderKeyDistributionMessage` ([SignalService.proto](https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto)).
  - **[inferred]** The pair (sender, sent timestamp) acts as the client-side message identity for receipts, edits and dedup.

### 2.5 E2EE
- **Published specs:** XEdDSA, X3DH, **PQXDH** (post-quantum key agreement), **Double Ratchet**, **Sesame** (sessions across multiple devices) and the ML-KEM Braid ([signal.org/docs](https://signal.org/docs/)).
- **SPQR.** Signal added the Sparse Post-Quantum Ratchet and runs it alongside the Double Ratchet, a combination it calls the "Triple Ratchet" ([Signal blog: SPQR](https://signal.org/blog/spqr/)).
- **Groups, first generation.** Signal sent "a pairwise encrypted message to each member", and "the server doesn't need to know about the concept of a 'group'" ([Signal blog: private groups](https://signal.org/blog/private-groups/)).
- **Groups, current generation.** The Signal Private Group System stores **encrypted group state on the server**. Members prove membership with zero-knowledge anonymous credentials, so there is one source of truth for membership and roles without the server learning who the members are ([Signal blog: private group system](https://signal.org/blog/signal-private-group-system/)).
  - Message sending uses Sender Keys, carried as `senderKeyDistributionMessage` in `Content` ([SignalService.proto](https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto)), together with the multi-recipient send endpoint and group send endorsement tokens ([MessageController.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java)).
  - **Lesson:** pure client-side group state led to conflicting concurrent membership changes, so Signal moved group state back onto the server, encrypted ([blog](https://signal.org/blog/signal-private-group-system/)).

### 2.6 Multi-device, media, push, receipts, discovery
- **Multi-device.** All devices share identity keys, "but every device has its own unique set of keys for encrypting and decrypting messages". Linking works by QR code with a provisioning message.
  - History moves as an encrypted archive under a one-time AES-256 key sent inside provisioning.
  - Media is not re-uploaded. The archive points at attachments still inside the **45-day attachment retention window** ([Signal blog: linked devices](https://signal.org/blog/a-synchronized-start-for-linked-devices/)).
- **Media.** `AttachmentControllerV4` returns "an upload form that can be used to perform a resumable upload" plus a CDN number (2 or 3). Implementations are `GcsAttachmentGenerator` and `TusAttachmentGenerator` ([AttachmentControllerV4.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/AttachmentControllerV4.java), [attachments/](https://github.com/signalapp/Signal-Server/tree/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/attachments)).
  - The message carries an `AttachmentPointer`: `cdnKey`, `key`, `digest`, `incrementalMac`, `size`, `blurHash`, `width`/`height` and `clientUuid` ([SignalService.proto](https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto)).
  - **The server only ever sees ciphertext blobs.**
- **Push carries no content.** FCM sends a data message whose key is `newMessageAlert`, with HIGH or NORMAL priority depending on `urgent` ([FcmSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/FcmSender.java)).
  - APNs sends either `mutable-content` with the placeholder alert `APN_Message` (the Notification Service Extension fetches and decrypts) or a `content-available` background push ([APNSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/APNSender.java)).
- **Typing and receipts are ordinary encrypted messages** (see 2.4). Typing indicators are sent as `ephemeral`/online-only, so they are neither stored nor pushed ([MessageSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java)). Signal has **no presence feature**.
- **Contact discovery.** Contact discovery runs inside an SGX enclave so the service can match phone numbers "without learning the content of the data or the result" ([Signal blog: private contact discovery](https://signal.org/blog/private-contact-discovery/), [faster ORAM](https://signal.org/blog/building-faster-oram/)).

---

## 3. Element / Matrix

### 3.1 Topology, identity, metadata
- **Federated.** Users are `@localpart:domain` on their homeserver ([spec: users](https://spec.matrix.org/latest/#users)). Devices exist mainly to hold E2EE keys ([spec: devices](https://spec.matrix.org/latest/#devices)).
- **Emails and phone numbers are optional** and go through a separate Identity Service ([identity service API](https://spec.matrix.org/latest/identity-service-api/)).
- **What servers can see:**
  - Room state, because servers must resolve it: membership, power levels and so on ([s2s: state resolution](https://spec.matrix.org/latest/server-server-api/#room-state-resolution)).
  - Ephemeral EDUs (typing, receipts, presence) ([s2s: EDUs](https://spec.matrix.org/latest/server-server-api/#edus)).
  - Megolm envelope metadata: `sender_key`, `device_id`, `session_id` ([m.megolm.v1](https://spec.matrix.org/latest/client-server-api/#mmegolmv1aes-sha2)).

### 3.2 Server architecture (Synapse)
- **Stack.** Python/Twisted ([pyproject](https://github.com/element-hq/synapse/blob/develop/pyproject.toml)). Workers require Postgres; "SQLite should only be used for demo purposes" ([workers.md](https://github.com/element-hq/synapse/blob/develop/docs/workers.md)).
- **Workers.** Separate processes share data through a replication protocol over Redis pub/sub and call each other over internal HTTP for request/response. Types include `generic_worker`, `pusher`, `federation_sender`, `media_repository` and `appservice` ([workers.md](https://github.com/element-hq/synapse/blob/develop/docs/workers.md)).
  - **Stream writers** are the single writers for `events`, `typing`, `to_device`, `receipts`, `presence` and so on. `events` can be sharded across event persisters by room ID ([workers.md#stream-writers](https://github.com/element-hq/synapse/blob/develop/docs/workers.md#stream-writers)).
- **Streams.** A stream is "an append-only log … of facts", each with a bigint stream ID, backed by a table. Multi-writer IDs come from a Postgres `SEQUENCE`. The client receives a composite `StreamToken` ([streams.md](https://github.com/element-hq/synapse/blob/develop/docs/development/synapse_architecture/streams.md)).
  - **This is the pattern to copy:** a monotonic per-stream ID in Postgres, exposed to clients as an opaque cursor.
- **Event DAG.** Each event lists `prev_events` (the current forward extremities) and `auth_events` ([s2s: PDUs](https://spec.matrix.org/latest/server-server-api/#pdus)). Conflicts are handled by state resolution, versioned per room version; v12 is recommended ([room versions](https://spec.matrix.org/latest/rooms/)).
  - Federation sends transactions of "at most 50 PDUs and 100 EDUs" ([s2s: transactions](https://spec.matrix.org/latest/server-server-api/#transactions)) and fills holes with `/backfill` and `/get_missing_events` ([s2s: backfill](https://spec.matrix.org/latest/server-server-api/#backfilling-and-retrieving-missing-events)).
  - Failed destinations are retried with backoff ([retryutils.py](https://github.com/element-hq/synapse/blob/develop/synapse/util/retryutils.py)).
- **Two orderings.** `stream_ordering` is arrival order and auto-increments; backfilled events count down from -1. `topological_ordering` is DAG depth.
  - Incremental `/sync` follows stream order. `/messages` and backfill follow DAG order ([room-dag-concepts.md](https://github.com/element-hq/synapse/blob/develop/docs/development/room-dag-concepts.md)).

### 3.3 Client-server sync
- **`/sync`.** A long-poll with `since=next_batch`. Each room returns a `prev_batch`. If too many events arrived, the timeline is **`limited`**, and the client fills the gap with `/rooms/{id}/messages?from=prev_batch` ([spec: syncing](https://spec.matrix.org/latest/client-server-api/#syncing)).
- **Sliding sync.** MSC3575 is obsolete. **MSC4186 Simplified Sliding Sync** was merged on 2026-06-29 but is not yet in spec v1.19 ([MSC4186](https://github.com/matrix-org/matrix-spec-proposals/pull/4186)).
  - Synapse implements it natively with windowed room lists, `pos` tokens, and extensions for to-device, E2EE, typing and receipts ([sync.py](https://github.com/element-hq/synapse/blob/develop/synapse/rest/client/sync.py)).
  - matrix-rust-sdk targets it ([sliding_sync](https://github.com/matrix-org/matrix-rust-sdk/blob/main/crates/matrix-sdk/src/sliding_sync/mod.rs)).
- **Idempotent sends.** `PUT /rooms/{roomId}/send/{eventType}/{txnId}`. The spec says: "allow the homeserver to distinguish a new request from a retransmission … so that it can make the request idempotent".
  - A retransmission gets "the same HTTP response code and content as the original request".
  - The scope is one device plus one endpoint, and the recommended ID is a UUIDv4 ([spec: transaction identifiers](https://spec.matrix.org/latest/client-server-api/#transaction-identifiers)).
- **Event IDs** are reference hashes from room v3 on, and are opaque to clients ([rooms/v3](https://spec.matrix.org/latest/rooms/v3/)).

### 3.4 Client architecture
- **matrix-rust-sdk** crates: `matrix-sdk`, `-base`, `-crypto`, `-sqlite`, `-store-encryption`, `-ui` (Timeline, RoomListService, SyncService, notification client, UTD hook) and `-ffi` ([crates](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates), [matrix-sdk-ui](https://github.com/matrix-org/matrix-rust-sdk/tree/main/crates/matrix-sdk-ui/src)).
- **Persistent send queue** ([send_queue/mod.rs](https://github.com/matrix-org/matrix-rust-sdk/blob/main/crates/matrix-sdk/src/send_queue/mod.rs)):
  - One queue task per room, which sends events in order.
  - Retries, and on an unrecoverable error the request is marked "wedged" so later events are never sent out of order.
  - Unsent events are persisted and resumed at startup.
  - Editing or aborting an unsent event is a purely local operation.
  - A media event depends on its upload finishing first.
- **Local store.** SQLite with values encrypted by `matrix-sdk-store-encryption` (PBKDF2 → XChaCha20-Poly1305) ([store-encryption](https://github.com/matrix-org/matrix-rust-sdk/blob/main/crates/matrix-sdk-store-encryption/src/lib.rs)).
- **Native UI layer.** Element X Android and iOS consume the SDK through **UniFFI** bindings: `org.matrix.rustcomponents:sdk-android` ([libs.versions.toml](https://github.com/element-hq/element-x-android/blob/develop/gradle/libs.versions.toml)) and `matrix-rust-components-swift` ([project.yml](https://github.com/element-hq/element-x-ios/blob/develop/project.yml), [ffi README](https://github.com/matrix-org/matrix-rust-sdk/blob/main/bindings/matrix-sdk-ffi/README.md)).
- **matrix-js-sdk** uses the Rust crypto compiled to WASM ([package.json](https://github.com/matrix-org/matrix-js-sdk/blob/develop/package.json)).

### 3.5 E2EE
- **Olm** provides pairwise device sessions (one-time and fallback keys) and carries room keys over to-device messages ([spec: key distribution](https://spec.matrix.org/latest/client-server-api/#key-distribution)).
- **Megolm** is a per-sender group ratchet: an HMAC-SHA-256 hash ratchet, AES-CBC, and Ed25519 signatures. Both are implemented in Rust as **vodozemac** ([vodozemac](https://github.com/matrix-org/vodozemac)).
- **Megolm's documented limitations** include **no post-compromise security** and **only partial forward secrecy**, since a leaked ratchet state decrypts every later message in that session ([megolm limitations](https://spec.matrix.org/latest/olm-megolm/megolm/#limitations)).
  - The practical cost is "unable to to decrypt" handling. Matrix works around it with key requests, server-side key backup, SSSS, withheld-key codes, and (v1.19) encrypted history sharing (MSC4268) ([spec: sharing keys](https://spec.matrix.org/latest/client-server-api/#sharing-keys-between-devices), [v1.19 changelog](https://github.com/matrix-org/matrix-spec/blob/main/content/changelog/v1.19.md)).
- **Device trust** uses cross-signing and SAS/QR verification ([spec: cross-signing](https://spec.matrix.org/latest/client-server-api/#cross-signing)).
- **MLS is not shipped.** MSC2883 "Matrix-flavoured MLS" is WIP with the label needs-implementation, and MSC4256 (RFC 9420) is still open ([MSC4256](https://github.com/matrix-org/matrix-spec-proposals/pull/4256)).

### 3.6 Receipts, typing, presence, media, push, abuse
- **Typing** is an EDU. The server "does not remember" users who aren't typing. The client re-sends `PUT typing` with a timeout and sends `false` when the user stops ([spec: typing](https://spec.matrix.org/latest/client-server-api/#typing-notifications)).
- **Receipts** `m.read` / `m.read.private` are per-event watermarks, and threaded receipts add a `thread_id` ([spec: receipts](https://spec.matrix.org/latest/client-server-api/#receipts)).
- **Presence** can be disabled or set to `"untracked"` in Synapse ([config docs](https://github.com/element-hq/synapse/blob/develop/docs/usage/configuration/config_documentation.md#presence)).
- **Media** lives in a content repository.
  - Uploads return `mxc://server/mediaId`.
  - Downloads have required auth since v1.11.
  - Async upload means `POST /media/v1/create` first, then `PUT` ([spec: content repo](https://spec.matrix.org/latest/client-server-api/#content-repository), [content-repo.yaml](https://github.com/matrix-org/matrix-spec/blob/main/data/api/client-server/content-repo.yaml)).
  - Encrypted attachments use a single-use AES-CTR key, with the ciphertext hash checked by the client, and the key travels inside the encrypted event ([spec: encrypted attachments](https://spec.matrix.org/latest/client-server-api/#sending-encrypted-attachments)).
- **Push.** The homeserver evaluates push rules and posts to a Push Gateway, retrying with backoff ([spec: push](https://spec.matrix.org/latest/client-server-api/#push-notifications), [push gateway API](https://spec.matrix.org/latest/push-gateway-api/)).
  - Sygnal forwards to APNs, FCM and WebPush.
  - With `event_id_only`, FCM/APNs only receive IDs. The app wakes up, fetches, decrypts and runs push rules locally ([sygnal applications.md](https://github.com/matrix-org/sygnal/blob/main/docs/applications.md)).
- **Contact discovery.** The client fetches a pepper, hashes `"<address> <medium> <pepper>"` with SHA-256, and calls `/lookup` ([identity: sha256](https://spec.matrix.org/latest/identity-service-api/#sha256)).
- **Abuse tools:**
  - Report endpoints for rooms, events and users ([report_content.yaml](https://github.com/matrix-org/matrix-spec/blob/main/data/api/client-server/report_content.yaml)).
  - Moderation policy lists `m.policy.rule.*` ([spec](https://spec.matrix.org/latest/client-server-api/#moderation-policy-lists)).
  - Server ACLs ([spec](https://spec.matrix.org/latest/client-server-api/#server-access-control-lists-acls-for-rooms)).
  - Policy Servers ([s2s](https://spec.matrix.org/latest/server-server-api/#policy-servers)).
  - Synapse `rc_*` rate limits ([config docs](https://github.com/element-hq/synapse/blob/develop/docs/usage/configuration/config_documentation.md)).
- **Registration.** User-interactive auth with recaptcha, email or registration-token stages ([spec: UIA](https://spec.matrix.org/latest/client-server-api/#user-interactive-authentication-api)).

---

## 4. SimpleX Chat

*`MQ` = `https://github.com/simplex-chat/simplexmq/blob/stable`, `CH` = `https://github.com/simplex-chat/simplex-chat/blob/stable`; links written out in full.*

### 4.1 Topology, identity, metadata
- **No user identifiers.** SMP "does not use any form of participants' identities". Instead there are unidirectional queues, and the router generates different recipient and sender IDs for each queue ([simplex-messaging.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/simplex-messaging.md)).
  - Every contact gets its own pairwise queues, which are handed over out of band as links or QR codes ([agent-protocol.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/agent-protocol.md)).
- **What routers know.** Queue activity, timing, and the recipient's IP (unless Tor is used). They do not see content or the sender's IP when private routing is on ([security.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/security.md)).
- **Private routing.** The sender reaches the destination router through a proxy router of its choice (`PRXY`/`PFWD`/`RFWD`) ([simplex-messaging.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/simplex-messaging.md#proxying-sender-commands)).
  - It became the default in v6.0 ([blog](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20240814-simplex-chat-vision-funding-v6-private-routing-new-user-experience.md)).
  - Preset routers come from two operators, SimpleX Chat and Flux, and the app uses different operators for receiving and for forwarding ([blog](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20241125-servers-operated-by-flux-true-privacy-and-decentralization-for-all-users.md)).

### 4.2 Server architecture
- **Two Haskell routers:** SMP (messaging) and XFTP (files).
- **Storage options:** queues in memory with an append-only store log, or in Postgres; messages in memory or in a journal ([Init.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/Messaging/Server/Main/Init.hs)).
- **Defaults:** messages expire after 21 days, and each queue holds up to 128 messages ([Env/STM.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/Messaging/Server/Env/STM.hs)).
- **Delivery.** After `SUB`, the router sends **one** `MSG` at a time and holds the next until the client sends `ACK <msgId>`. Because the ACK names the message ID, a repeated ACK cannot delete the wrong message ([simplex-messaging.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/simplex-messaging.md)).
  - Offline delivery needs nothing extra: the queue simply holds messages until the recipient subscribes and acks.
- **Transport.** TLS 1.3 only, with the client pinning the router's certificate fingerprint. Every transport block is exactly **16384 bytes**, so traffic looks uniform. WebSocket support is "deprecated and should be used for testing only" ([simplex-messaging.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/simplex-messaging.md), [Init.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/Messaging/Server/Main/Init.hs)).

### 4.3 Agent and chat protocol layers
- **Duplex connections** are built from two simplex queues, one in each direction. The connection can rotate to new queues on other routers (`QADD`/`QKEY`/`QUSE`/`QTEST`) ([agent-protocol.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/agent-protocol.md)).
- **Integrity.** Every agent message carries a sequential ID and **the hash of the previous message**. The agent raises `MsgSkipped`, `MsgBadId`, `MsgBadHash` or `MsgDuplicate` when these don't line up ([agent-protocol.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/agent-protocol.md), [Protocol.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/Messaging/Agent/Protocol.hs)).
- **Retry schedule.** Fast retries start at 2s and cap at 120s. Slow retries start at 5 min and cap at 6h. A message times out after 2 days ([Agent/Env/SQLite.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/Messaging/Agent/Env/SQLite.hs)).
- **Chat protocol.** JSON events such as `x.msg.new`, `x.msg.update`, `x.msg.del`, `x.msg.react`, `x.msg.file.descr`, `x.grp.*` and `x.call.*` ([simplex-chat.md](https://github.com/simplex-chat/simplex-chat/blob/stable/docs/protocol/simplex-chat.md), [Protocol.hs](https://github.com/simplex-chat/simplex-chat/blob/stable/src/Simplex/Chat/Protocol.hs)).

### 4.4 Client architecture
- **The whole client core is Haskell,** compiled into each app and exposed through a C FFI that passes **JSON strings** (`chat_migrate_init_key`, `chat_send_cmd`, `chat_recv_msg_wait`, …) ([Mobile.hs](https://github.com/simplex-chat/simplex-chat/blob/stable/src/Simplex/Chat/Mobile.hs)).
  - The UI sends commands and reads an event stream. The UI layer is Kotlin (Android/desktop) or Swift (iOS, with Notification Service and Share extensions) ([apps/](https://github.com/simplex-chat/simplex-chat/tree/stable/apps)).
  - **This is the closest analogue to Convoze's Riverpod plan:** a single core that owns state and emits events, with a thin UI on top.
- **Local store.** SQLite encrypted with SQLCipher (`direct-sqlcipher`, `sqlcipher-simple`) ([simplex-chat.cabal](https://github.com/simplex-chat/simplex-chat/blob/stable/simplex-chat.cabal)). The passphrase is random by default ([managing-data.md](https://github.com/simplex-chat/simplex-chat/blob/stable/docs/guide/managing-data.md)).
- **No real multi-device.** Desktop pairs with the phone over the local network (XRCP) and **remote-controls the phone's core** ([xrcp.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/xrcp.md)).

### 4.5 E2EE and groups
- **Layers of encryption:**
  - A double ratchet (Curve448, AES-GCM) with an optional **sntrup761** post-quantum KEM step.
  - A NaCl `crypto_box` layer per queue between sender and recipient.
  - A separate router-to-recipient layer, so incoming and outgoing traffic at a router can't be matched.
  - TLS underneath ([security.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/security.md), [pqdr.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/pqdr.md)).
  - PQ is on by default for direct chats since v5.7 ([blog](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20240426-simplex-legally-binding-transparency-v5-7-better-user-experience.md)).
- **Groups are fully peer-to-peer.** Every member holds a pairwise connection to every other member, and new members are introduced by the member who invited them. That inviter could act as a man in the middle ([simplex-chat.md](https://github.com/simplex-chat/simplex-chat/blob/stable/docs/protocol/simplex-chat.md#decentralized-design-for-chat-groups)).
  - Each message is sent N times. The design aimed at about 100 members, but public groups have reached thousands ([blog: large groups](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20250114-simplex-network-large-groups-privacy-preserving-content-moderation.md)).
- **Channels (v6.5, April 2026)** send through relay members. **Relay operators can see channel content**, but not who the participants are ([channels-overview.md](https://github.com/simplex-chat/simplex-chat/blob/stable/docs/protocol/channels-overview.md), [blog](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20260430-simplex-channels-v6-5-consortium-crowdfunding-freedom-of-speech.md)).

### 4.6 Media, push, receipts, abuse
- **XFTP.** The file is padded, encrypted, and split into fixed-size chunks (64KB–4MB). Chunks go to several routers, and each recipient gets different chunk IDs. The "file description" (keys, digests, replicas) travels over SMP. Maximum size is 1 GB, and files expire after 48h by default ([xftp.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/xftp.md), [Description.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/FileTransfer/Description.hs), [Server/Env.hs](https://github.com/simplex-chat/simplexmq/blob/stable/src/Simplex/FileTransfer/Server/Env.hs)).
- **Push on iOS.** A notification router subscribes to the user's queues (`NSUB`) and sends APNs pushes whose metadata is encrypted and which carry no message content. The Notification Service Extension then `GET`s the message ([push-notifications.md](https://github.com/simplex-chat/simplexmq/blob/stable/protocol/push-notifications.md)).
- **Push on Android.** There is **no FCM**: the app runs a foreground service or a periodic WorkManager job (every 600s) ([SimpleXAPI.kt](https://github.com/simplex-chat/simplex-chat/blob/stable/apps/multiplatform/common/src/commonMain/kotlin/chat/simplex/common/model/SimpleXAPI.kt), [MessagesFetcherWorker.kt](https://github.com/simplex-chat/simplex-chat/blob/stable/apps/multiplatform/android/src/main/java/chat/simplex/app/MessagesFetcherWorker.kt)).
- **No presence and no typing event.** The closest feature is "live messages", which update as you type ([blog v4.4](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20230103-simplex-chat-v4.4-disappearing-messages.md)).
  - Delivery receipts are agent-level `A_RCVD` messages carrying the message ID and hash, sent only for certain message types ([Protocol.hs](https://github.com/simplex-chat/simplex-chat/blob/stable/src/Simplex/Chat/Protocol.hs), [blog v5.2](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20230722-simplex-chat-v5-2-message-delivery-receipts.md)).
- **No contact discovery;** contacts are added only by link or QR. For abuse:
  - Group-level tools: reports to admins, observer role, member review ([blog v6.3](https://github.com/simplex-chat/simplex-chat/blob/stable/blog/20250308-simplex-chat-v6-3-new-user-experience-safety-in-public-groups.md)).
  - Operators can block specific reported files or group links on their own routers without scanning content ([content-moderation RFC](https://github.com/simplex-chat/simplex-chat/blob/stable/docs/rfcs/2024-12-30-content-moderation.md)).

---

## 5. Telegram

### 5.1 Topology, identity, metadata
- **Centralized cloud split into data centers.** "user information is accumulated in the DC with which the user is associated". Logging in on the wrong DC returns `PHONE_MIGRATE_X`/`NETWORK_MIGRATE_X`, and sessions move between DCs with `auth.exportAuthorization`/`importAuthorization` ([api/datacenter](https://core.telegram.org/api/datacenter)).
- **Identity.** "Telegram uses phone numbers as unique identifiers" ([privacy](https://telegram.org/privacy)). Optional usernames make you findable without sharing a number ([FAQ](https://telegram.org/faq)).
- **Cloud chat storage.** Messages are stored "heavily encrypted and the encryption keys … stored in several other data centers" ([privacy §3.3.1](https://telegram.org/privacy)). **[inferred]** This is encryption at rest only; Telegram's servers can read cloud chats.
- **Metadata.** IP, devices, and username history are kept for 12 months ([privacy](https://telegram.org/privacy)).

### 5.2 Server and transport (documented contract)
- **Transports.** TCP with abridged/intermediate/padded framing, WebSocket (obfuscation required), and HTTP long-poll via `http_wait` ([mtproto-transports](https://core.telegram.org/mtproto/mtproto-transports), [transports](https://core.telegram.org/mtproto/transports), [service_messages](https://core.telegram.org/mtproto/service_messages)).
- **Separate media connections.** Large file transfers should use separate sessions to `media_only` DCs, and those sessions "never carry updates" ([api/datacenter](https://core.telegram.org/api/datacenter)).
- **CDN DCs** cache media from big public channels. They are treated as "enemy territory": files are AES-256-CTR encrypted with per-part SHA-256 hashes ([cdn](https://core.telegram.org/cdn)).
- **Keys and sessions.** Each device has its own auth key per DC, created by Diffie-Hellman and never sent over the network. The client picks a random session ID, and the server may forget sessions ([mtproto/description](https://core.telegram.org/mtproto/description)).

### 5.3 MTProto message layer (reliability)
- **`msg_id`.** About unixtime·2^32, generated by the client, monotonic, and divisible by 4. Messages more than 300s in the past or 30s in the future are ignored, and receivers drop duplicates ([description](https://core.telegram.org/mtproto/description)).
- **`seq_no` and acks.** `seq_no` counts content-related messages. `msgs_ack` acknowledges receipt, and the server resends unacked content over a new connection ([description](https://core.telegram.org/mtproto/description), [service_messages_about_messages](https://core.telegram.org/mtproto/service_messages_about_messages)).
- **Resending.** A message is never resent under the same `msg_id`; the client re-wraps it or asks with `msgs_state_req` ([same](https://core.telegram.org/mtproto/service_messages_about_messages)).
- **Ordering.** Parallel requests run "in arbitrary order" unless wrapped in `invokeAfterMsg` ([api/invoking](https://core.telegram.org/api/invoking)).

### 5.4 Updates and sync, in depth
Source: [core.telegram.org/api/updates](https://core.telegram.org/api/updates) unless noted.

- **Event sequences a client tracks:**
  - **`pts`:** one common message box per account, covering private chats and basic groups.
  - **`pts` per channel/supergroup:** one separate counter per channel.
  - **`qts`:** secret chats and certain bot events.
  - **`seq`:** sequencing for the `updates`/`updatesCombined` containers.
- **Gap rule** for an update carrying `(pts, pts_count)`:
  - `local_pts + pts_count == pts` → apply the update and set `local_pts = pts`.
  - `local_pts + pts_count > pts` → already applied; ignore it (dedup).
  - `local_pts + pts_count < pts` → a gap. Wait up to **0.5s** for reordered updates, then call `updates.getDifference`.
- **When to call `getDifference`:**
  - On startup.
  - On any gap.
  - On `new_session_created`.
  - On an update that can't be parsed or is missing data.
  - After **15 minutes with no updates**.
  - On `updatesTooLong`/`updateChannelTooLong`.
- **`updates.getDifference(pts, date, qts, …)`** returns one of:
  - `differenceEmpty`.
  - `difference` (new messages, other updates, users/chats, new state).
  - `differenceSlice`: store the intermediate state and call again.
  - `differenceTooLong`: re-fetch state and fill history separately ([method](https://core.telegram.org/method/updates.getDifference)).
- **`updates.getChannelDifference(channel, pts, limit)`** returns an explicit `final` flag and a `timeout`. The client polls open channels this way, up to 10 at a time ([method](https://core.telegram.org/method/updates.getChannelDifference)).
  - Recommended limits are "10-100 for channels and 1000-10000 otherwise".
  - Server-side mailbox size is "usually … 100000 for channels and 5000000 for the common message box".
- **What the client persists:** `pts`/`qts`/`seq`/`date` plus a `pts` for each channel. Messages are stored by ID; gaps left by deleted messages "must not be 'filled'". Socket updates are held back while a gap is being filled.
- **Send dedup with `random_id`** (quoted): "if the client attempts invoking a method passing a random_id which was already used … from any session of the current account at any time in the past (used random_ids stored by the server do not expire), the method call will simply return the messages generated by the previous method call … if the previous method call is currently inflight … a RANDOM_ID_DUPLICATE error will be emitted".
  - `updateMessageID(id, random_id)` maps the client's ID to the server's. If the RPC response is lost, it is delivered again through `getDifference` ([api/updates](https://core.telegram.org/api/updates), [messages.sendMessage](https://core.telegram.org/method/messages.sendMessage)).
- **Message ID spaces.** Private chats and basic groups share one monotonic ID sequence per account. Each channel has its own sequence, identical for all users ([api/updates](https://core.telegram.org/api/updates)).
- **Pagination.** `offset_id` + `add_offset` + `limit` + `max_id`/`min_id`, plus a 64-bit `hash` over cached IDs so the server can answer "not modified" ([api/offsets](https://core.telegram.org/api/offsets)).

### 5.5 Client architecture
- **TDLib** is a C++17 cross-platform client core. It "guarantees that all updates are delivered in the right order", encrypts local data with a user-supplied key, and exposes a JSON API: `td_create_client_id`, `td_send`, `td_receive` ([README](https://github.com/tdlib/td/blob/master/README.md), [td_json_client.h](https://github.com/tdlib/td/blob/master/td/telegram/td_json_client.h)).
  - `setTdlibParameters` takes `database_encryption_key` and the `use_message_database` flags ([td_api.tl](https://github.com/tdlib/td/blob/master/td/generate/scheme/td_api.tl)).
  - The repo contains `sqlite/` and `tddb/` directories. **[inferred]** The local database is SQLite.
- **Official apps mostly don't use TDLib.**
  - Telegram X uses it ([apps](https://telegram.org/apps)).
  - Telegram-Android has its own C++ MTProto stack in `jni/tgnet` ([repo](https://github.com/DrKLO/Telegram)).
  - iOS uses Swift `MtProtoKit`/`Postbox`/`TelegramCore` ([repo](https://github.com/TelegramMessenger/Telegram-iOS)), and macOS shares that code ([.gitmodules](https://github.com/overtake/TelegramSwift/blob/master/.gitmodules)).
  - tdesktop is C++/Qt ([repo](https://github.com/telegramdesktop/tdesktop)).

### 5.6 Encryption
- **Client-server encryption (MTProto 2.0).** AES-256-IGE, with `msg_key` taken from SHA-256 over the auth key plus plaintext ([description](https://core.telegram.org/mtproto/description)).
- **Cloud chats are not end-to-end encrypted:** "Server-client encryption is used in Cloud Chats … Secret Chats use an additional layer of client-client encryption" ([FAQ](https://telegram.org/faq)).
- **Secret chats:**
  - 1:1 only, created by Diffie-Hellman, and bound to **one device** (the recipient's other devices get `encryptedChatDiscarded`) ([api/end-to-end](https://core.telegram.org/api/end-to-end)).
  - Re-keyed after 100 messages or one week ([pfs](https://core.telegram.org/api/end-to-end/pfs)).
  - Their own in/out `seq_no` handles gap and resend detection ([seq_no](https://core.telegram.org/api/end-to-end/seq_no)).
- **What server access enables:**
  - Unlimited devices synced from the cloud.
  - Groups of up to 200,000 members and unlimited channels ([FAQ](https://telegram.org/faq)).
  - Server-side search: `messages.search`, `messages.searchGlobal` ([search](https://core.telegram.org/method/messages.search)).
  - Bots and CDN caching.
  - **This is the exact tradeoff Convoze faces (see §8).**

### 5.7 Multi-device, media, push, presence, discovery, abuse
- **Multi-device.** A device is just an authorization that reads the shared cloud mailboxes. `account.getAuthorizations` lists them. QR login is `auth.exportLoginToken` → `acceptLoginToken` → `updateLoginToken` ([qr-login](https://core.telegram.org/api/qr-login), [getAuthorizations](https://core.telegram.org/method/account.getAuthorizations)).
- **Files.**
  - Uploads use `upload.saveFilePart`/`saveBigFilePart` with 512 KB parts, which can be sent in parallel and are held temporarily until the message that uses them is sent.
  - Downloads use `upload.getFile(location, offset, limit)` in 1 MB chunks.
  - `file_reference` expires and must be refreshed ([api/files](https://core.telegram.org/api/files)).
  - `messages.getDocumentByHash` reuses existing uploads for some media types ([api/files](https://core.telegram.org/api/files)).
- **Push.**
  - `account.registerDevice(token_type, token, secret, …)` supports APNs, FCM, WebPush and others, and should be re-registered at least every 24h ([registerDevice](https://core.telegram.org/method/account.registerDevice)).
  - The payload's `loc_key`/`loc_args` templates include the sender and **message text**, e.g. `MESSAGE_TEXT` = "{1}: {2}". An optional `secret` encrypts FCM/VoIP payloads with MTProto ([api/push-updates](https://core.telegram.org/api/push-updates)).
- **Presence.**
  - `userStatusOnline(expires)`/`Offline(was_online)`, plus fuzzy "recently / last week / last month" values when privacy settings apply ([userStatusRecently](https://core.telegram.org/constructor/userStatusRecently), [FAQ](https://telegram.org/faq)).
  - Clients set it with `account.updateStatus`, and the config supplies timing values ([updateStatus](https://core.telegram.org/method/account.updateStatus)).
- **Typing.** `messages.setTyping(peer, action)`. The typing update "is valid for 6 seconds", after which the client should consider typing stopped. Actions include upload progress ([setTyping](https://core.telegram.org/method/messages.setTyping), [updateUserTyping](https://core.telegram.org/constructor/updateUserTyping)).
- **Read receipts are a watermark.**
  - `messages.readHistory(peer, max_id)` generates `updateReadHistoryInbox`/`Outbox`, both of which advance `pts`.
  - Dialogs store `read_inbox_max_id` and `read_outbox_max_id` ([readHistory](https://core.telegram.org/method/messages.readHistory), [dialog](https://core.telegram.org/constructor/dialog)).
- **Discovery.** `contacts.importContacts` uploads phone numbers, filtered by privacy settings. Usernames are found with `contacts.search`/`resolveUsername` ([api/contacts](https://core.telegram.org/api/contacts)).
- **Abuse:**
  - Rate limits surface as `FLOOD_WAIT_X` (420) ([errors](https://core.telegram.org/api/errors)).
  - `messages.report` is a multi-step flow ([report](https://core.telegram.org/method/messages.report)).
  - Reported messages are reviewed by moderators, spammers can be restricted from contacting strangers, and @SpamBot handles appeals ([privacy §5.3](https://telegram.org/privacy)).
- **Registration:**
  - `auth.sendCode` → `signIn`/`signUp`. Codes can arrive in-app, by SMS, call, flash/missed call, email, Fragment or Firebase SMS ([auth.SentCodeType](https://core.telegram.org/type/auth.SentCodeType)).
  - `auth.resendCode` switches to the next delivery method, and `PHONE_NUMBER_FLOOD` limits abuse ([api/auth](https://core.telegram.org/api/auth), [sendCode](https://core.telegram.org/method/auth.sendCode)).
  - The 2FA password is checked with SRP ([api/srp](https://core.telegram.org/api/srp)).

---

## 6. WhatsApp

*Main sources:*
- *WP: [Encryption Overview v9](https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf)*
- *MD: [multi-device post (2021)](https://engineering.fb.com/2021/07/14/security/whatsapp-multi-device/)*
- *INTEROP: [interoperability post (2024)](https://engineering.fb.com/2024/03/06/security/whatsapp-messenger-messaging-interoperability-eu/)*
- *PP: [privacy policy](https://www.whatsapp.com/legal/privacy-policy)*
- *Rick Reed's Erlang Factory talks: [2012](https://www.erlang-factory.com/upload/presentations/558/efsf2012-whatsapp-scaling.pdf) and [2014](https://www.erlang-factory.com/static/upload/media/1394350183453526efsf2014whatsappscaling.pdf)*

*Help Center facts marked (FAQ) come from search extracts of official pages that need JavaScript to render; re-check them in a browser.*

### 6.1 Topology, identity, metadata
- **Centralized, with server-side fan-out for groups** (WP, "Group Messages").
- **Each account has one primary phone** registered with a phone number (WP, Terms).
  - Usernames were announced, with reservations opening in June 2026 and launch "later this year" ([Meta newsroom](https://about.fb.com/news/2026/06/its-time-to-reserve-your-whatsapp-username/)). [unverified] whether they are live yet.
- **Server-side data** (PP):
  - Delivered messages "are deleted from our servers". Undelivered ones are kept encrypted "for up to 30 days".
  - The server does see: group name/picture/description, online and last-seen status, device and connection data, IP.
- **Call logs.** WhatsApp says it does not keep logs of who messages or calls whom ([calls post](https://engineering.fb.com/2023/11/08/security/whatsapp-calls-enhancing-security/)).

### 6.2 Backend
- **Erlang on FreeBSD** (Reed 2012).
  - 2012: one server peaked at **2.8M connections**.
  - 2014: ~550 servers, ~150 chat servers at "~1M phones each", 147M concurrent connections, and peaks of 342K messages in and 712K out per second (Reed 2014).
- **Mnesia.** Services are split into 2–32 partitions, with records pinned to a node by hash. Mnesia "islands" hold 2 nodes each. Offline storage was a known I/O bottleneck: "most messages picked up very quickly", which led to a write-back cache (Reed 2014).
- **Erlang is still used today** (WhatsApp open-sources [eqwalizer](https://github.com/WhatsApp/eqwalizer) and [erlfmt](https://github.com/WhatsApp/erlfmt)).
- **The front end is "ChatD"** ([E2EE backups post](https://engineering.fb.com/2021/09/10/security/whatsapp-e2ee-backups/)). Its protocol is "based on … XMPP" with "optimized XML stanzas" (INTEROP).
  - "FunXMPP"/ejabberd ancestry: [3P only, unverified].

### 6.3 Transport
- **Noise Pipes with Curve25519, AES-GCM and SHA256** on a long-running connection. The server stores only the client's public auth key (WP, "Transport Security").
- **Third-party clients** perform a Noise handshake on every connection and receive pushed messages over a persistent connection (INTEROP).

### 6.4 E2EE
- **Signal Protocol** (WP; [Signal announcement](https://signal.org/blog/whatsapp-complete/)).
  - Keys: identity key, signed prekey and one-time prekeys.
  - Session setup: 4 ECDH results → HKDF. Messages use AES-256-CBC + HMAC-SHA256, with a hash ratchet plus a DH ratchet on each round trip.
- **Groups use Sender Keys.** Each sender generates a chain key and a signature key and sends them to each member over pairwise sessions. After that, each message is **one ciphertext that the server fans out**.
  - "Whenever a group member leaves, all group participants clear their Sender Key and start over" (WP).
  - **[inferred]** Tradeoff: sends are O(1) and forward secrecy comes from the hash ratchet, but there is no post-compromise recovery until the key is reset, and the reset costs O(n) when membership changes.
- **Media.** The client encrypts with AES-CBC + HMAC and uploads to a **blob store**. The message carries the key, the SHA256 of the blob and a pointer. The receiver checks the hash and MAC before decrypting (WP).
- **Key transparency.** An Auditable Key Directory ([akd, Rust](https://github.com/facebook/akd)) with verification now automatic on Android and iOS ([KT post](https://engineering.fb.com/2023/04/13/security/whatsapp-key-transparency/)).
- **E2EE backups.** An HSM-based Backup Key Vault with OPAQUE ([backups whitepaper v2](https://www.whatsapp.com/security/WhatsApp_Security_Encrypted_Backups_Whitepaper.pdf)).
- **Post-quantum E2EE:** [unverified]. WP v9 lists only Curve25519, AES and HMAC.

### 6.5 Multi-device, in depth
- **Each device is its own identity.** "each device now has its own identity key. The WhatsApp server maintains a mapping between each person's account and all their device identities"; you can use a phone plus up to four other devices "even if your phone battery is dead" (MD). Linked devices must be re-validated by logging in on the primary every 14 days ([FAQ](https://faq.whatsapp.com/378279804439436)).
- **Linking** (WP):
  1. The companion shows a QR code containing its identity key and a one-time linking secret.
  2. The primary signs `0x0600||metadata||I_companion` (Account Signature) and a new device list `0x0602||ListData`, then uploads them with an HMAC.
  3. The companion checks both and counter-signs `0x0601||…` (Device Signature).
  4. The companion uploads its prekeys.
  - An alternative 8-character code flow uses PBKDF2 plus ECDH.
- **Client fanout** (WP/MD):
  - The sender encrypts **once for every device** of the recipient **and once for each of its own other devices**.
  - A device whose signatures don't verify is skipped.
  - Every pairwise ciphertext carries the timestamp of the latest signed device list, so peers notice changes to the list.
- **Server-assisted consistency** (WP):
  - The server compares a hash of the sender's target device list with its own records. On a mismatch, the sender fetches the list and re-encrypts for the missing devices.
  - Signed device lists expire after at most 35 days.
  - Reinstalling on the primary revokes all companions.
- **History sync** (WP/MD): right after linking, the primary encrypts recent chats as blobs, uploads them, and sends the keys over E2EE. The companion imports and deletes them.
- **App state sync ("syncd")** (WP):
  - **Collections:** settings such as mute, pin, archive, star, "deleted for me" and contact names are kept as **collections of index→value mutations**. A batch of mutations is a **patch**, which moves a collection from version N to N+1.
  - **Server storage:** the server keeps a patch queue for recent days, and a "Base Roller" compacts it into snapshots.
  - **Encryption:** indexes are replaced by HMAC values. Values are padded and encrypted with AES-CBC + HMAC-SHA512.
  - **Anti-tamper:** clients keep an **LtHash** over each collection's state plus a snapshot MAC and patch MAC. A patch's version must match the version the server assigns.
  - **Key rotation:** on device removal and periodically, with gradual re-encryption.
  - **[inferred]** This is an end-to-end encrypted version of "versioned op-log + snapshot compaction", which works whether or not the data is encrypted.

### 6.6 Push, receipts, groups, discovery, abuse
- **Push.** The Erlang architecture diagram includes a Push service (Reed 2014). The client "wakes up and retrieves the offline message from WhatsApp server" ([device verification post](https://engineering.fb.com/2023/04/13/security/whatsapp-device-verification-protects-your-account/)). The contents of FCM/APNs payloads are [unverified].
- **Ticks** (FAQ, [665923838265756](https://faq.whatsapp.com/665923838265756)):
  - One grey tick: sent.
  - Two grey: delivered "to the recipient's phone or any of their linked devices".
  - Blue: read.
  - In groups, the ticks change only once **every** member has received or read the message.
  - Read receipts can be turned off.
- **Last seen and online** audience settings are reciprocal: if you hide yours, you can't see others' ([FAQ](https://faq.whatsapp.com/419827870318306)). Whether receipts and typing are E2EE: [unverified]; PP lists "message receipts" and online status as data other users can see.
- **Groups and channels.**
  - Groups hold up to 1,024 members. Communities hold up to 100 groups ([FAQ](https://faq.whatsapp.com/438859978317289)).
  - Channels are **not** E2EE: E2EE Channels are listed as a possible future feature ([channels privacy policy](https://www.whatsapp.com/legal/channels-privacy-policy)).
- **Discovery.** The client uploads the address book "on a regular basis". Non-users are handled so "those contacts cannot be identified by us" (PP).
- **Abuse:**
  - A report sends the **last five messages** from the reported party to WhatsApp ([FAQ](https://faq.whatsapp.com/414631957536067)).
  - An on-device scam detection model runs on messages from non-contacts ([Scam Alert post](https://engineering.fb.com/2026/08/12/security/how-were-building-scam-alert-whatsapp/)).
  - "Silence unknown callers" works with server-checked privacy tokens ([calls post](https://engineering.fb.com/2023/11/08/security/whatsapp-calls-enhancing-security/)).
  - Forwarding limits: [3P only].
- **Registration.** A 6-digit code by SMS or voice call (or email), with an optional 2-step verification PIN ([FAQ](https://faq.whatsapp.com/506595211487528)).
- **Interop (EU DMA).** Third-party clients connect directly to WhatsApp servers, authenticate with a JWT, and use the Signal Protocol. They host their own media, which Meta clients fetch through a proxy (INTEROP).

---

## 7. Cross-cutting patterns

1. **The server holds a per-device inbox; the client acks; the server deletes.**
   - Signal: Redis sorted set per device, acked by GUID.
   - SimpleX: queue with ACK by msgId.
   - WhatsApp: delete on delivery, 30-day cap.
   - **Contrast:** Telegram and Matrix keep full history on the server and sync the client to a cursor instead.
   - Convoze stores full history in Postgres like Telegram and Matrix, so the **cursor model** fits better.
2. **Every sync design has a monotonic sequence and a gap rule.**
   - Telegram `pts` + `pts_count` → `getDifference`.
   - Matrix `next_batch` + `limited`/`prev_batch`.
   - SimpleX sequential ID + previous hash.
   - WhatsApp syncd patch version N→N+1.
   - Signal `queue/empty` marks the end of the catch-up.
3. **Client-generated IDs make sends idempotent.**
   - Matrix `txnId`: the server replays the original response.
   - Telegram `random_id`: kept forever and mapped to the server ID by `updateMessageID`.
   - Signal: client timestamp plus server GUID.
4. **Send queues persist, stay ordered, and survive restarts.** matrix-rust-sdk's per-room queue marks a failed request "wedged" rather than sending later messages out of order. SimpleX retries with backoff for up to 2 days.
5. **Ephemeral signals are kept separate from stored messages.**
   - Signal `ephemeral`/online-only envelopes.
   - Matrix EDUs outside the DAG.
   - Telegram typing that expires after 6s via `updateShort`.
   - None of them persist typing indicators, and none push them.
6. **Read receipts are watermarks, not per-message rows.** Telegram's `read_inbox_max_id`/`read_outbox_max_id` and Matrix's `m.read` on the latest event both work this way. Signal sends receipts that list message timestamps.
7. **Media never goes through the message path.**
   - Upload a blob (resumable or chunked), then send a small pointer with key/hash/size/dimensions/thumbnail.
   - Signal: upload form → CDN.
   - Matrix: `create` then `PUT`.
   - Telegram: parts, then the message references the upload.
   - WhatsApp/SimpleX: encrypted blob plus description.
8. **Push is a wake-up signal.**
   - Signal, SimpleX and Matrix `event_id_only` send no content. The app fetches and renders the notification itself (Notification Service Extension on iOS).
   - Telegram is the exception: its push payloads include the message text.
9. **Moving to E2EE removes server features.** Server search, server-side push rules, moderation of content and server-held history all disappear. Telegram keeps cloud chats non-E2EE to retain them. Signal, WhatsApp and Matrix give them up and rebuild some parts on the client or in enclaves.
10. **Group state needs one source of truth.** Signal dropped pure client-side group state because concurrent edits conflicted. Matrix needs full state resolution to cope with federation. A centralized Convoze gets this for free by keeping group state in Postgres.

---

## 8. Lessons for Convoze

Convoze today (from [`features.md`](../features.md) and [ADR 0001](../adr/0001-flutter-client-architecture.md)):
- **Backend:** Node/Express + Postgres (recommended in features.md) + Socket.IO. Rooms per user and per conversation.
- **Auth:** JWT access + refresh tokens; the ADR adds phone + OTP.
- **Message model:** a `Message` row with a `status` of `sent | delivered | seen`.
- **Client:** Flutter with Riverpod (`StreamProvider`/`AsyncNotifier`), GoRouter, Dio, feature-first `data`/`presentation` layout. There is no local database yet.

Recommendations are grouped by when to act:
- **P0:** do it in the 1-week MVP. Each is cheap now and expensive to retrofit.
- **P1:** design the seam now, build it later.
- **P2:** later, and only if product needs change.

### P0: do now (1-week MVP)

**P0-1. Client-generated message IDs make sends idempotent** (Matrix `txnId`, Telegram `random_id`).
- **Schema:** add `clientMsgId UUID` to `Message` with `UNIQUE (senderId, clientMsgId)`.
- **Socket.IO send:** `sendMessage({conversationId, clientMsgId, type, content})` becomes `INSERT … ON CONFLICT (senderId, clientMsgId) DO NOTHING RETURNING *`. On conflict, select the existing row and return **the same ack payload** (`{clientMsgId, id, seq, createdAt}`), exactly as Matrix replays the original response.
- **Always use Socket.IO acks** (the callback argument). The client matches ack to pending message by `clientMsgId`, the same way Telegram uses `updateMessageID`.
- **Retries:** because retries are now safe, the client can resend after a reconnect without creating duplicate messages.

**P0-2. A per-conversation sequence number used as the sync cursor** (Telegram per-channel `pts`, Synapse stream IDs).
- **Schema:** add `seq BIGINT` to `Message` with `UNIQUE (conversationId, seq)`.
- **Assigning `seq`:** inside the insert transaction, run `UPDATE conversations SET last_seq = last_seq + 1 WHERE id = $1 RETURNING last_seq`. The row lock serializes concurrent writers per conversation, which is fine at MVP scale.
- **Ordering and pagination:** order and paginate on `seq`, not `createdAt`. That replaces the `createdAt` cursor in features.md #14, since clock ties and skew make `createdAt` unreliable.
  - History endpoint: `GET /conversations/:id/messages?beforeSeq=&limit=30`.
- **Edits, deletes and reactions** (features #10/#11) should **also take a new `seq`**, either as event rows or by bumping a `Message.updatedSeq`. The catch-up query then returns changes as well as new messages. This is Telegram's rule that edits and read-history updates also advance `pts`.

**P0-3. WebSocket for live updates, REST for catch-up. Don't rely on Socket.IO rooms alone.**
- **The problem:** Socket.IO rooms only reach sockets that are connected at that moment. Anything emitted while a client is disconnected, reconnecting or backgrounded is lost. features.md #2 says the message "still saves to DB for later retrieval", but doesn't define *how* a client retrieves it.
- **The rule to add** (Telegram's gap rule, simplified):
  - Client stores `lastSeq` per conversation, and a global `lastEventId` if you add a user-level event stream later.
  - On connect or reconnect, and on app resume: `GET /sync?since=<cursor>` returns the conversations and messages that changed after the cursor, capped by a `limit`, with a `hasMore` flag (Telegram `differenceSlice`, Matrix `limited`).
  - A live `receiveMessage` whose `seq` is exactly `lastSeq + 1` is applied immediately. A **higher** `seq` means a gap: call the catch-up REST endpoint for that conversation. A **lower or equal** `seq` is a duplicate and is ignored.
  - Also run catch-up on a timer if nothing has arrived for a while (Telegram re-syncs after 15 minutes of silence).
- **MVP-sized implementation:** a single `GET /conversations?updatedSince=` plus a per-conversation `GET /conversations/:id/messages?afterSeq=` is enough. You don't need a global event log yet.

**P0-4. Keep ephemeral events separate from persisted ones** (Signal `ephemeral`, Matrix EDUs, Telegram's 6s typing).
- **Typing** (#5): relay only and never write it to the DB. Give it a **TTL on the client**: show "typing…" for about 6s after the last `typing` event even if `stopTyping` never arrives. The `stopTyping` event gets lost when a socket drops. Never send push for typing.
- **Presence** (#4): features.md already suggests Redis for scaling. For the MVP, count **sockets per user** in memory, not a single `socketId`. `Map<userId, socketId>` in features.md breaks as soon as a user has two tabs or devices.
  - Emit `userOffline` only when the count reaches 0, preferably after a short grace period (a few seconds) so network blips don't flicker.
  - Store `lastSeenAt` in Postgres on disconnect.
  - Send presence only to users who share a conversation, never globally. WhatsApp and Telegram add privacy settings for last seen; those can wait.
- **In code:** name the socket events so the difference is obvious, e.g. `ephemeral:typing` vs `event:message`.

**P0-5. Read receipts as per-member watermarks, not per-message status** (Telegram `read_inbox_max_id`, Matrix `m.read`).
- **The problem:** `Message.status: sent|delivered|seen` in features.md only works for 1:1 chats. In a group, "seen" depends on the member (WhatsApp only turns ticks blue once *every* member has read).
- **The change:** move it to `Participant.lastReadSeq` and `Participant.lastDeliveredSeq`.
  - `markAsRead({conversationId, seq})` only ever moves forward: `UPDATE … SET lastReadSeq = GREATEST(lastReadSeq, $seq)`.
  - Unread count = `conversation.last_seq - participant.lastReadSeq`, minus the user's own messages if needed.
- **Ticks computed on the client:**
  - A message is "delivered" when `seq <= min(other participants' lastDeliveredSeq)`.
  - It is "seen" when `seq <= min(other participants' lastReadSeq)`.
  - The server sends `receipt` events carrying `{userId, conversationId, lastReadSeq}`.
- **Payoff:** one update per read event instead of N row updates, and it works the same for 1:1 and groups.

**P0-6. Media: upload first, then send a pointer.** Don't stream blobs through the message path (Signal upload form → CDN, Matrix `create`+`PUT`, Telegram parts).
- **Upload endpoint:** keep `POST /media` (multer, local disk) for the week, but make it return an `attachmentId` plus metadata (`mime`, `size`, `width`, `height`, `sha256`).
- **Message payload:** send `{type:'image', attachmentId, …}` over the socket; the server validates ownership and size.
- **Swap later:** the client code doesn't change when `POST /media` is replaced by S3/R2 **pre-signed URLs** (`POST /media/uploads` → `{uploadUrl, attachmentId}` → client PUTs straight to object storage → `POST /media/uploads/:id/complete`). This is the P1 step.
- **Metadata:** add `blurHash` or a tiny thumbnail and dimensions, so Flutter can lay out the bubble before the image downloads (Signal `AttachmentPointer.blurHash`/`width`/`height`).
- **Validation:** validate MIME type by content sniffing on the server (features.md #9 already says don't trust the client).

**P0-7. Client local store + outbox. This belongs in the ADR** (matrix-rust-sdk send queue, SimpleX/Signal SQLite, TDLib).
- **Local database:** add **drift** (SQLite) under `lib/core/db/` with tables `conversations`, `messages` (including `clientMsgId`, `seq` nullable while pending, `state: pending|sent|failed`), `sync_state` (cursor per conversation) and `outbox`.
- **Read path:** the UI reads **only** from drift. Riverpod `StreamProvider`s watch drift queries. The socket and REST repositories write into drift; they never push straight to widgets. This is the SimpleX, TDLib and Element X shape (core owns state, UI subscribes) expressed in Riverpod, and it matches ADR 0001's "repository pattern in `data`".
- **Sending:**
  1. Insert the message into drift as `pending` with a new `clientMsgId`, so the bubble appears instantly.
  2. Add an outbox row.
  3. An `OutboxWorker` provider sends one message at a time **per conversation, in order**, and waits for the ack.
  4. On ack, store `id`/`seq` and set `state=sent`.
  5. On a transient error, retry with exponential backoff.
  6. On a permanent error (4xx, blocked), mark `failed`, stop that conversation's queue ("wedged", as matrix-rust-sdk does) and show "tap to retry".
- **Media dependency:** media messages wait for their upload to finish (matrix-rust-sdk's dependency system).
- **Encryption at rest:** skip it for the MVP. Leave the seam: the SQLCipher-based drift setup is one constructor change later.

**P0-8. Push with no content, triggered from the delivery path** (Signal `newMessageAlert`, Matrix `event_id_only`, SimpleX).
- **Payload:** FCM **data** message `{type:'message', conversationId, seq}`. The app wakes, runs catch-up (P0-3), and builds the local notification from drift.
  - For an MVP you may put sender and preview in a `notification` payload for simplicity, as Telegram does. Keep it behind one server function (`buildPush(message)`) so the switch to content-free (required if E2EE ever ships) is a single change.
  - iOS can't display data-only pushes reliably without an extension. Signal uses a `mutable-content` alert plus a Notification Service Extension ([APNSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/APNSender.java)).
- **When to push:** only when the user has **zero connected sockets**, or no focused socket (Signal `MessageSender`). Never for ephemeral events.
- **Device tokens:** keep a `Device` table `{id, userId, platform, pushToken, lastSeenAt}` and refresh the token on each app start (Telegram asks for re-registration at least every 24h).

**P0-9. Phone + OTP done Signal's way** ([VerificationController](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/VerificationController.java), Telegram [auth](https://core.telegram.org/api/auth)).
- **A verification session**, not a bare `POST /otp`:
  - `POST /auth/verification` `{phone}` → `{sessionId, allowedToRequestCode, nextCodeAt, requestedInformation[]}`.
  - `POST /auth/verification/:id/code` `{transport:'sms'}`.
  - `PUT /auth/verification/:id/code` `{code}` → JWT access + refresh tokens and a `deviceId`.
- **Rate limits** per phone, per IP and per session, with a growing delay between resends, returned as `nextCodeAt` or 429 + `Retry-After` (Signal 429; Telegram `FLOOD_WAIT_X`, `PHONE_NUMBER_FLOOD`).
- **Code hygiene:** codes are short-lived (about 5–10 min), stored as a hash, limited to a few attempts, and single-use. Normalize numbers to E.164.
- **Seam for later:** the `requestedInformation` array is where a captcha or app-attestation challenge plugs in once SMS pumping starts costing money. Signal gates `allowedToRequestCode` on exactly that.
- **Tokens:** issue refresh tokens **per device** (`Device` row) so "log out other devices" and push-token cleanup work. This is Telegram's `account.getAuthorizations` model. Rotate refresh tokens on use.
- **Update features.md #1:** it still describes `register/login` with bcrypt passwords. The ADR's phone+OTP replaces that.

**P0-10. Put blocking and rate limiting in the delivery path, not only in routes.**
- **Blocking:** check `Block` inside the one `deliverMessage()` service function used by both the socket and REST paths (features #16).
- **Rate limiting:** limit `sendMessage` per user **and** per new conversation. The spam risk is cold outreach to strangers, which is why Telegram restricts reported users from "contacting strangers" and WhatsApp runs scam detection on messages from non-contacts.
- **Reports:** have a report capture message IDs **plus a snapshot of the last N messages** (WhatsApp sends the last 5, [FAQ](https://faq.whatsapp.com/414631957536067)). Content may be edited or deleted later, and a future move to E2EE would take server access away.

### P1: design the seam now, build after MVP

**P1-1. A user-level event log for multi-device and cheap sync** (Telegram's common `pts` box, Synapse streams).
- **Why:** per-conversation `seq` (P0-2) needs one query per conversation to catch up. The next step is a `user_events(userId, eventId BIGSERIAL, type, payload, createdAt)` table, or a Postgres sequence per user, written in the same transaction as the message.
- **What it gives:** `GET /sync?since=eventId&limit=500` → `{events, nextSince, hasMore}`, the same shape as `getDifference`/`differenceSlice`. Membership changes, reads on other devices, profile updates and blocks all become events.
- **Retention:** prune old events. When a client's cursor is older than what's kept, return `tooLong` (Telegram `differenceTooLong`) so the client resets and refetches recent history.

**P1-2. Multi-device as a first-class concept.** Even without E2EE, model `Device` now: tokens, push token, `lastSyncCursor`.
- **Your own actions:** with a per-user event log, a message you send from device A reaches device B as a normal event, and read watermarks sync because they are server state.
- **Contrast with WhatsApp:** it needs client fanout, signed device lists and syncd *only because of E2EE*. Don't copy that machinery unless Convoze adopts E2EE.
- **Device linking:** Telegram's QR login (`exportLoginToken`/`acceptLoginToken`) is a good pattern for adding a desktop or web client without SMS.

**P1-3. Horizontal scale for Socket.IO.**
- **Why:** an in-memory presence `Map` and Socket.IO rooms only work on one Node process.
- **The seam:** hide them behind `PresenceStore` and `Fanout` interfaces now. Later, back them with the Redis adapter for Socket.IO (fanout) and Redis sets with TTL for presence.
- **Delivery doesn't change:** because it goes through the DB plus the seq/cursor sync, a missed cross-node emit is just a gap the client repairs (Synapse workers stream from Postgres through Redis in the same way).

**P1-4. Object storage + CDN for media.** Pre-signed PUT uploads, private buckets, and short-lived signed download URLs (Matrix made media downloads require auth in v1.11; Telegram's `file_reference` expires).
- Add resumable/chunked upload for video (Signal TUS, Telegram parts).
- Dedup by content hash per uploader if storage cost matters (Telegram `getDocumentByHash`).
- Run a retention job for orphaned uploads that were never attached to a message.

**P1-5. Search that survives a later move to E2EE.**
- **MVP:** Postgres full-text search (`tsvector` + GIN), which is better than `LIKE` (features #13).
- **The seam:** the Flutter search UI calls a `SearchRepository`. Today it hits the server. With E2EE it would query a local drift FTS5 index instead, the way Signal and WhatsApp search on-device. With the local store (P0-7) in place, local FTS is cheap to add either way.

**P1-6. A message envelope that separates content from routing.** Shape messages as `{id, clientMsgId, conversationId, senderId, senderDeviceId, seq, type, createdAt, body}`, where `body` is a JSON blob the server treats as opaque except for validation and search indexing.
- This mirrors Signal's opaque `content` field and Matrix's `content` vs event envelope.
- If E2EE arrives, `body` becomes ciphertext and routing is unchanged.

### P2: E2EE decision (later, and only for a concrete reason)

**Recommendation:** don't build E2EE for the MVP. Adopt it only if privacy is a product requirement, and decide knowingly, because it forces these changes (evidence in §§2–7):

| Feature (features.md) | Non-E2EE (Telegram-like, current plan) | With E2EE (Signal/WhatsApp-like) |
|---|---|---|
| #13 Search | Postgres FTS on the server | Only on the device (local FTS); new devices can't search old history unless it is transferred |
| #12 Push previews | Server can put a preview in the push | Content-free push; client decrypts in a Notification Service Extension or background handler |
| #16 Reporting / moderation | Server reads content | Reporter's client must send plaintext (WhatsApp's last 5 messages); no server scanning, only metadata-based spam controls |
| #3 History on new device / reinstall | Server holds it | Needs primary-to-companion transfer (Signal archive, WhatsApp history sync) or encrypted backups (WhatsApp HSM vault) |
| #8 Groups | Server-side membership, one copy per message | Sender Keys (O(1) sends; re-key when anyone leaves) or MLS; membership changes become cryptographic events |
| #9 Media | Server can transcode, thumbnail, scan | Client encrypts; the server stores ciphertext; thumbnails and blurhash are created on the client and travel inside the message |
| Multi-device | Trivial (sessions on the cloud) | Per-device identity keys, device lists, fanout to every device (WhatsApp client fanout; Matrix UTDs) |
| #10 Edit/delete | Server updates the row | Edit and delete become new encrypted messages the client applies (Signal `EditMessage`) |

- **If E2EE is adopted:**
  - Use **libsignal** (Rust, maintained; bindings for Java/Swift/TS, so a Flutter FFI wrapper or platform channels would be needed, since there is no official Dart binding) rather than writing crypto yourself ([libsignal](https://github.com/signalapp/libsignal)).
  - Server side: add prekey endpoints (identity key, signed prekey, one-time prekeys **and** Kyber prekeys for PQXDH) and a per-device inbox with ack-delete (Signal `MessagesCache` pattern). Run it next to the history store, which then holds only ciphertext.
  - Plan groups with Sender Keys first. Signal and WhatsApp both ship it. Megolm's documented weaknesses and Matrix's UTD work show that group key distribution is the hard part.
  - Keep the server-owned group membership you already have (P0), as Signal's move to server-held group state shows is the right call.
- **Middle ground if privacy is wanted without E2EE:**
  - Encrypt at rest (Postgres/KMS column encryption).
  - Keep push content-free.
  - Minimize metadata retention (Telegram keeps metadata 12 months; WhatsApp deletes delivered messages).
  - Encrypt the local drift database with SQLCipher (Signal-Android, SimpleX).

### Summary: suggested changes to existing docs
- **features.md data model:**
  - `Message` += `clientMsgId` (unique per sender), `seq` (unique per conversation), `senderDeviceId`, `updatedSeq`; drop `status`.
  - `Participant` += `lastReadSeq`, `lastDeliveredSeq`.
  - `Conversation` += `lastSeq`.
  - New tables `Device`, `Attachment`, `VerificationSession`.
  - #14 pagination cursor: `seq` instead of `createdAt`.
  - #1 auth: replace password flow with phone+OTP sessions.
- **ADR 0001 follow-ups** (new ADRs):
  - (a) drift local store + outbox, UI reads only from drift.
  - (b) sync protocol: socket live events + REST catch-up with a `seq` cursor, including gap rule and dedup.
  - (c) push payload policy (content-free).
  - (d) explicit non-goal: no E2EE in v1, with the seams from P1-6/P1-5 kept.
