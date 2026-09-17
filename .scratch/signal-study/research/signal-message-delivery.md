# Signal-Server message delivery: queue, ack, and wake-up push

Research for issue #12 (part of map #10). Informs **Delivery pipeline design over Socket.IO**.
Decision already taken: Postgres-backed store-and-forward queue with ack-delete, content-free push, separate attachment upload. This note supplies the detail for that design.

Signal code is AGPL-3.0. Everything below describes behaviour in prose; no code is copied.

**Sources pinned to:** Signal-Server commit `b30fc7aa8bc825025e51400751feac4e65f15d13` (shallow clone, 2026-09-17). Abbreviation used below:
`SS` = `https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13`
`SVC` = `SS/service/src/main/java/org/whispersystems/textsecuregcm`

---

## 1. Transport: one WebSocket, request/response framing in both directions

- The socket carries protobuf `WebSocketMessage`s of type `REQUEST` or `RESPONSE`. A request has `verb`, `path`, `headers`, `body`, and a numeric `id`. A response echoes `id` and adds an HTTP-style `status`. So both sides can make "HTTP-like" calls over the same socket. ([WebSocketProtocol.proto](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/websocket-resources/src/main/proto/WebSocketProtocol.proto))
- The server *pushes* each message to the client as a request: `PUT /api/v1/message` with the serialized `Envelope` as body. When the backlog is drained it sends `PUT /api/v1/queue/empty`. ([WebSocketConnection.java L180, L250](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java))
- The socket is used for both message delivery and client API calls. A device counts as "present" while its socket is open. ([RedisMessageAvailabilityManager.java class javadoc](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/RedisMessageAvailabilityManager.java))
- The WebSocket environment's default idle timeout is 60 s. ([WebSocketEnvironment.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/websocket-resources/src/main/java/org/whispersystems/websocket/setup/WebSocketEnvironment.java))

## 2. Sending and enqueueing

- **Queues are per device, not per user.** The sender submits one ciphertext per destination device, keyed by device ID, each with a registration ID. The server rejects the send with **409** (devices missing or extra) or **410** (stale registration IDs). The client then fixes its device list or sessions and resends. ([MessageController.java L168–L430](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java); [MessageSender.java `sendMessages`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java))
- **Size cap:** each message's content is limited to 96 KiB (`MAX_MESSAGE_SIZE`). Attachments therefore go through a separate upload path (`/v4/attachments/form/upload`). ([MessageSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java); [AttachmentControllerV4.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/AttachmentControllerV4.java))
- **Envelope fields** include `type`, `source_service_id`/`source_device` (absent for sealed sender), `client_timestamp` (the sender's ID for the message), `server_timestamp`, `server_guid` (a 16-byte UUID assigned by the server), `ephemeral`, `urgent` (default true), `story`, and opaque `content`. ([TextSecure.proto `Envelope`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/proto/TextSecure.proto))
- **The send path:** the message is inserted into each destination device's queue, and the insert reports whether that device is currently present. If a device is *not present* and the message is *not ephemeral*, the server sends a push notification. Ephemeral ("online-only", e.g. typing) messages never trigger a push. ([MessageSender.java `sendMessages`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java); [MessagesManager.java `insert`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java))
- **Group fan-out:** a multi-recipient send stores the shared payload once. Each device's queue gets a small envelope that points to it (`shared_mrm_key`). A device's view is removed when it is delivered, and key expiry acts as backup garbage collection. ([MessagesCache.java class javadoc](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java); [MessagesManager.java `insertMultiRecipientMessage`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java))

## 3. Storage: hot cache in front of a durable store

- **Hot tier (Redis), per device:**
  - a sorted set of envelopes, scored by a queue-local counter that only increases;
  - a hash mapping message GUID to that counter, plus the `counter` field itself;
  - a lock key that the persister sets while it moves the queue.
  ([MessagesCache.java javadoc L64–L114](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java))
- **Idempotent insert by GUID:** the insert script first checks whether the GUID is already in the metadata hash. If it is, the script returns the existing ID and does not add a second copy. Otherwise it increments the counter, adds the envelope, records the GUID, sets a 46-day expiry, and publishes a "message available" event on the device's pub/sub channel. The return value is whether a listener received that event, which is how presence is detected. ([insert_item.lua](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/resources/lua/insert_item.lua))
- **Paged reads in order:** reads fetch pages of 100 envelopes with score greater than the last one seen. While the persister holds the lock, reads return an empty list. ([get_items.lua](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/resources/lua/get_items.lua); [MessagesCache.java `PAGE_SIZE`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java))
- **Durable tier (DynamoDB):** `MessagePersister` moves queues whose oldest message is older than `persistDelay` into DynamoDB, in batches of 100, then removes them from Redis. The default `persistDelayMinutes` is 10. Ephemeral messages are dropped rather than persisted. DynamoDB rows get a TTL of `server_timestamp + expiration`, and the sample config uses `P30D`. ([MessagePersister.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagePersister.java); [MessageCacheConfiguration.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/configuration/MessageCacheConfiguration.java); [MessagesCache.java `getMessagesToPersist`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java); [MessagesDynamoDb.java TTL](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesDynamoDb.java); [test.yml](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/test/resources/config/test.yml))
- **Read order is durable first, then cache:** a device's stream reads the persisted (older) messages first, then the cached ones. This keeps the order oldest-first. ([MessagesManager.java `getMessagesForDevice`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java))
- **Stale ephemeral messages are dropped on read:** ephemeral messages older than `MAX_EPHEMERAL_MESSAGE_DELAY` (10 s) are discarded instead of delivered. ([MessagesCache.java L162, L303–L345](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesCache.java))
- Signal is migrating storage to FoundationDB behind experiment flags. The contract stays the same: an ordered stream plus acknowledge-by-GUID. ([MessagesManager.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java); [MessageStream.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessageStream.java))

## 4. Delivery, acknowledgement, deletion

- **On connect** the server does three things:
  1. cancels any scheduled pushes for this device;
  2. subscribes to the device's message stream (non-terminating, with at most one `QueueEmpty` marker);
  3. sends envelopes as they arrive.
  Delivery uses `flatMapSequential` with up to 256 concurrent in-flight sends, so completions are handled in stream order even though sends overlap. ([WebSocketConnection.java `start`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java); [MessageStream.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessageStream.java))
- **Ack means a 2xx response to the server's `PUT /api/v1/message`.** Only then does the server call `acknowledgeMessage(guid, serverTimestamp)`. That call removes the message from the cache by GUID, or deletes it from DynamoDB if it was already persisted. A non-2xx response or a timeout leaves the message queued, so it is redelivered on the next connection. This is **at-least-once** delivery. ([WebSocketConnection.java `sendMessage`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java); [RedisDynamoDbMessageStream.java `acknowledgeMessage`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/RedisDynamoDbMessageStream.java); [MessagesManager.java `delete`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java))
- **Delivery receipts are tied to the ack.** After a successful ack, the server itself sends a `SERVER_DELIVERY_RECEIPT` to the original sender carrying the message's `client_timestamp`. It does this only when the source is known (not sealed sender) and the envelope is not itself a receipt. So "delivered" means the recipient device took durable custody. Read receipts are a separate, end-to-end message. ([WebSocketConnection.java `sendMessage`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java); [ReceiptSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/ReceiptSender.java))
- **One consumer per device:** a new connection for the same device displaces the old one, which is closed with code `4409 "Connected elsewhere"`. The javadoc calls this best-effort, not a strict at-most-one guarantee. ([WebSocketConnection.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java); [RedisMessageAvailabilityManager.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/RedisMessageAvailabilityManager.java))
- **Disconnect with messages still queued:** on close, if the device may still have messages, the server schedules a delayed push 1 minute later (`CLOSE_WITH_PENDING_MESSAGES_NOTIFICATION_DELAY`). ([WebSocketConnection.java `stop`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java))
- **Duplicates are handled at both ends.** The server makes inserts idempotent by GUID (§3). Redelivery after a lost ack still produces duplicates, and the client drops them. Signal-Android logs "Duplicate message!" at decryption and has a `DUPLICATE_MESSAGE` state that is dropped during processing. Its message table has a unique index on `(date_sent, from_recipient_id, thread_id)`. ([MessageDecryptor.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/messages/MessageDecryptor.kt); [MessageContentProcessor.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/messages/MessageContentProcessor.kt); [MessageTable.kt `message_unique_sent_from_thread`](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/MessageTable.kt))

## 5. Push: content-free wake-ups

- **FCM** sends a data-only message whose single key is `newMessageAlert` with an empty value. Priority is `HIGH` if urgent and `NORMAL` otherwise, and the default TTL is 28 days. There is no message content, sender, or count. ([FcmSender.java `sendNotification`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/FcmSender.java))
- **APNs**, urgent case: an alert with `mutable-content: 1` and a fixed localized key `APN_Message`. The Notification Service Extension then fetches and decrypts the message on the device. The collapse ID is `incoming-message`. Non-urgent case: a background push (`content-available: 1`) with conserve-power priority. Default TTL is 30 days. ([APNSender.java L40–L135](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/APNSender.java))
- **Non-urgent pushes are not sent immediately.** They are handed to `PushNotificationScheduler`, which rate-limits background pushes to at most one per device per `BACKGROUND_NOTIFICATION_PERIOD` (20 min). Scheduled pushes are cancelled when the device connects. ([PushNotificationManager.java `sendNotification`, `handleMessagesRetrieved`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/PushNotificationManager.java); [PushNotificationScheduler.java L78](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/PushNotificationScheduler.java))
- **Token hygiene:** an FCM `UNREGISTERED` error or an APNs unregistered response clears the device's token. The token is cleared only if the invalidation is newer than the token and the token has not changed since. ([PushNotificationManager.java `handleDeviceUnregistered`, `clearPushToken`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/PushNotificationManager.java))
- **Client side of a wake-up:** Signal-Android's `FcmReceiveService.onMessageReceived` checks for challenge keys. Anything else is treated as a new-message wake-up: it starts a foreground or background fetch service and enqueues a fetch (`FcmFetchManager`). The fetch opens the socket and drains the queue as in §4. ([FcmReceiveService.java](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/gcm/FcmReceiveService.java))
- **Firebase constraints that shape this design:**
  - Data messages carry only custom key-value pairs, and the payload limit is 4096 bytes. ([FCM message types](https://firebase.google.com/docs/cloud-messaging/customize-messages/set-message-type))
  - High-priority messages can wake a device from Doze. If FCM "detects a pattern in which messages don't result in user-facing notifications", it may downgrade them to normal priority, judged over the last 7 days. ([FCM Android priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority))
  - TTL ranges from 0 to 28 days, and 28 days is the default. ([FCM lifespan](https://firebase.google.com/docs/cloud-messaging/customize-messages/setting-message-lifespan))

## 6. Rate limiting and abuse controls on send

- Every send passes the `MESSAGES` limiter, keyed by (sender, destination), with bucket config `60` / `1s`. It also passes an `INBOUND_MESSAGE_BYTES` limiter keyed by destination on total content length. Stories use their own `STORIES` limiter, and attachment creation uses `ATTACHMENT` and `ATTACHMENT_BYTES`. ([RateLimiters.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/limits/RateLimiters.java); [MessageController.java L266, L338, L374](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java))
- A spam check runs before enqueue and can reject the request. When the sender is known, a report-spam token is recorded per message GUID. Rate-limit *challenges* are delivered by push (`rateLimitChallenge`). ([MessageController.java L360–L366](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/controllers/MessageController.java); [MessagesManager.java `insertAsync`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/storage/MessagesManager.java); [FcmSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/FcmSender.java))
- A read-only switch in dynamic configuration can reject all sends. A `MessageDeliveryLoopMonitor` watches for devices that keep receiving the same first message, which is a sign of a crash or redelivery loop. ([MessageSender.java](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/push/MessageSender.java); [WebSocketConnection.java `start`](https://github.com/signalapp/Signal-Server/blob/b30fc7aa8bc825025e51400751feac4e65f15d13/service/src/main/java/org/whispersystems/textsecuregcm/websocket/WebSocketConnection.java))

## 7. Socket.IO facts that matter here

- **Default delivery is at-most-once.** Socket.IO keeps no server-side buffer, so a disconnected client misses events. Any stronger guarantee "must be implemented in your application". The docs' recommended server-to-client pattern is: give each event a unique ID, persist events in a database, have the client store its last offset and send it on reconnect. ([Delivery guarantees](https://socket.io/docs/v4/delivery-guarantees); source: [delivery-guarantees.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/01-Documentation/delivery-guarantees.md))
- **Ordering** is guaranteed within a connection, including across the long-polling to WebSocket upgrade. (same source)
- **Client-to-server at-least-once** is available through the client's `retries` and `ackTimeout` options. Pending events are still lost if the app or tab is killed. (same source)
- **Acks:** `socket.timeout(ms).emit(ev, ..., (err, res) => …)` has existed since v4.4. `socket.emitWithAck()` returns a Promise since v4.6, and it rejects when combined with `timeout()` and the deadline passes. ([Emitting events](https://socket.io/docs/v4/emitting-events/), source: [emitting-events.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/04-Events/emitting-events.md); [server-api.md `socket.emitWithAck`](https://github.com/socketio/socket.io-website/blob/main/docs/server-api.md))
- **Connection state recovery** restores `socket.id`, rooms, `data`, and missed packets for up to `maxDisconnectionDuration`. The docs say it "will not always be successful", tell you to still handle resynchronisation, and warn against setting the duration to `Infinity`. It is supported by the in-memory, Redis Streams, and MongoDB adapters. The Redis pub/sub adapter does not support it, and support in the **Postgres adapter is listed as NO/WIP**. ([Connection state recovery](https://socket.io/docs/v4/connection-state-recovery), source: [connection-state-recovery.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/01-Documentation/connection-state-recovery.md); [adapter-postgres.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/05-Adapters/adapter-postgres.md))
- **Postgres adapter:** it routes broadcasts across nodes using `LISTEN`/`NOTIFY`. Payloads that are binary or larger than 8000 bytes go through an auxiliary table. Broadcast-with-ack is supported. Sticky sessions are still needed when long-polling is used. ([adapter-postgres.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/05-Adapters/adapter-postgres.md); [adapter.md](https://github.com/socketio/socket.io-website/blob/main/docs/categories/05-Adapters/adapter.md))

## 8. Where Socket.IO diverges from Signal

| Concern | Signal | Socket.IO out of the box | Consequence for Convoze |
|---|---|---|---|
| Delivery guarantee | At-least-once. The server deletes a message only after a 2xx from the client. | At-most-once, no server buffer | Build the queue and ack yourself (already decided). |
| Missed-while-offline | Durable per-device queue, drained on connect | Connection state recovery is short-lived, best-effort, and not supported on the Postgres adapter | **Do not rely on CSR.** Treat the Postgres queue as the source of truth; CSR is at most an optimisation. |
| Ack channel | Response `status` to a server-initiated request | Ack callback, or `emitWithAck` plus `timeout` | Map a resolved ack to a 2xx; treat a timeout or error as "keep queued". |
| Consumer uniqueness | One stream per device, older one closed with 4409 | Many sockets per user are allowed | Enforce one socket per `(user, device)` yourself. |
| Presence for push decision | The insert publishes on a per-device channel; "someone received it" means present | Rooms plus adapter; `fetchSockets()` across nodes | Use a per-device room (`dev:<deviceId>`); push if no socket is in it. |
| Fan-out | Per-device ciphertext, shared group payload | Room broadcast | Store per-device queue rows. A room broadcast is only a *doorbell*. |

---

## Summary

Signal delivers messages from a **durable, per-device, ordered queue**:
- Each message gets a server GUID and a monotonic queue position.
- Messages go out over a long-lived socket as server-initiated requests.
- A message is **deleted only after the client acknowledges it**, and that ack is also what triggers the sender's "delivered" receipt.
- Delivery is at-least-once: inserts are idempotent by GUID, and clients drop duplicates.
- Devices that are not connected get a **push with no content** that only means "come fetch". Urgent pushes are sent now; non-urgent ones are coalesced to at most one per 20 minutes. Scheduled pushes are cancelled on connect, and a follow-up push is scheduled if a socket closes with messages still queued.
- Sends are rate-limited per (sender, destination) pair and per destination byte count, and message bodies are capped at 96 KiB, which forces attachments out of band.

Socket.IO gives none of this beyond ordering within a connection. Its connection state recovery is explicitly best-effort and is not available with the Postgres adapter.

## Translation: delivery pipeline over Socket.IO + Postgres

**Schema (sketch):**
```
devices(id uuid pk, user_id, fcm_token, apns_token, token_updated_at, last_seen_at)
message_queue(
  id           bigint generated always as identity,   -- monotonic position (Signal's queue-local counter)
  device_id    uuid not null references devices,
  guid         uuid not null,                          -- server GUID, used for ack
  sender_user_id, sender_device_id,
  client_msg_id text not null,                         -- sender-generated; idempotency key
  kind         smallint,                               -- message | receipt | ...
  urgent       bool default true,
  body         bytea/jsonb,                            -- <= e.g. 64-96 KiB; attachments are references only
  created_at   timestamptz default now(),
  expires_at   timestamptz not null,                   -- e.g. now() + 30 days
  primary key (device_id, id),
  unique (device_id, guid),
  unique (device_id, sender_device_id, client_msg_id)  -- idempotent retries from sender
)
```
Signal's two tiers (Redis, then DynamoDB) are a scaling optimisation. A single Postgres table covers the same logic at Convoze's scale. Run a periodic `DELETE … WHERE expires_at < now()`, or partition by time.

**Send (client to server):** `socket.emit('msg:send', payload, ack)`, with client `retries` and `ackTimeout` enabled.
1. Authenticate the socket, then check rate limits (Postgres or in-memory token bucket): per (sender, recipient) and bytes per recipient.
2. Validate the body size and that the recipient's device list matches. Return an error ack listing missing or extra devices, the equivalent of Signal's 409/410.
3. In one transaction, `INSERT … ON CONFLICT (device_id, sender_device_id, client_msg_id) DO NOTHING`, one row per recipient device. This makes sender retries safe.
4. After commit, ack the sender with `{guid, serverTs}`, which means "accepted by server".
5. For each device: `io.to('dev:'+deviceId).emit('queue:nudge')`, a doorbell with no payload. The adapter delivers it on whichever node holds the socket. If `fetchSockets()` on that room is empty and `urgent`, send push; if not urgent, schedule a coalesced push.

**Deliver (server to client):**
- On connect, run auth middleware, then:
  1. join `dev:<deviceId>`;
  2. disconnect any other socket already in that room (Signal's 4409);
  3. cancel pending scheduled pushes;
  4. start the drain loop.
- **Drain loop, one per socket, serialized:**
  1. `SELECT … WHERE device_id=$1 AND id > $cursor AND expires_at > now() ORDER BY id LIMIT 100`.
  2. For each row: `await socket.timeout(15000).emitWithAck('msg:deliver', row)`.
  3. On success: `DELETE FROM message_queue WHERE device_id=$1 AND guid=$2`, then enqueue a `delivered` receipt row to the sender's devices, whose delivery triggers their own nudge or push.
  4. On timeout or error: stop the loop and leave the rows. They are redelivered on the next connect or nudge.
  5. When a page comes back empty, emit `queue:empty`.
  6. A `queue:nudge` received while idle restarts the loop.
- You can pipeline sends like Signal (several emits in flight) as long as deletes are by GUID. Keeping one in-flight message at a time is simpler and keeps order exact.
- **Client:**
  - Persist the message locally before returning the ack, because the ack means "custody taken".
  - Dedupe on `guid`, and on `(sender, client_msg_id)` for resent messages.
  - Treat `queue:empty` as "caught up", for example to hide a syncing indicator.
- **Disconnect:** if the device still has rows, schedule a push about 1 minute later. It is cancelled if the device reconnects first.
- **Connection state recovery:** leave it off, or on only for UX smoothing. Correctness must come from the queue, since the Postgres adapter does not support it.
- **Ephemeral events (typing, presence):** send with `socket.volatile` or a plain room emit. Never write them to the queue and never push for them.

**Push:**
- The payload is data-only, for example `{t:"msg"}`: no body, sender, or preview. FCM priority is `high` only when urgent. On iOS, use `mutable-content` with a generic alert for urgent messages, or `content-available` otherwise.
- The TTL should be no longer than the queue retention. Use a collapse key or collapse ID such as `incoming-message` so a burst of messages leads to a single fetch.
- Coalesce non-urgent pushes to one per device per N minutes. A Postgres table `push_schedule(device_id pk, due_at)` polled by a worker is enough.
- Only mark urgent the messages the user will see as a notification. FCM downgrades high-priority senders whose pushes don't lead to a visible notification.
- Clear tokens on `UNREGISTERED`, but only if the token hasn't changed since the push was sent.

**Wake-up path (Flutter):** the FCM or APNs handler starts a short-lived background task that connects Socket.IO with stored credentials. It drains until `queue:empty` (with a hard time budget), then shows local notifications built from the decrypted or stored messages.

**Attachments:** upload out of band to object storage through a pre-signed URL, rate-limited per user and by bytes. The queued message carries only `{attachmentId/url, key/digest, size, mime}`, keeping `message_queue.body` small.
