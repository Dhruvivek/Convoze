# Signal: attachments, link previews, view-once media — and Convoze equivalents

Issue: #13 (part of the Signal study map, #10). Researched 2026-09-17.

**License note:** Signal's clients and server are AGPLv3. This note describes *behaviour and design* observed in Signal's public repos and first-party pages. No Signal code is copied here or should be copied into Convoze.

Sources are primary only: `github.com/signalapp/*` (read at `main` on the research date), signal.org / support.signal.org, AWS S3 docs, tus.io, pub.dev, and Android developer docs. Where a source could not be fetched directly or sources conflict, that is called out.

---

## 1. Attachments

### 1.1 Client-side encryption (before upload)

- Every attachment gets a fresh random key. On Android, `AttachmentCipherOutputStream` splits a 64-byte "combined key" into a 32-byte AES key and a 32-byte HMAC key, and encrypts with **AES-256-CBC + PKCS5 padding, then HMAC-SHA256** over `IV || ciphertext`. The output layout is `IV || ciphertext || MAC`.
  Source: https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/java/org/whispersystems/signalservice/api/crypto/AttachmentCipherOutputStream.kt
- Desktop does the same thing (`AES256CBC` cipher, SHA-256 `digest` over the encrypted blob). It can also compute an optional **`incrementalMac`** with libsignal's `incremental_mac`, so the client can check chunks while streaming instead of waiting for the whole file.
  Source: https://github.com/signalapp/Signal-Desktop/blob/main/ts/AttachmentCrypto.node.ts
- **Size padding:** the plaintext is padded before encryption, so the server/CDN only sees rounded-up sizes. The size is rounded up to the next power of 1.05, with a minimum of 541 bytes (`max(541, floor(1.05^ceil(log_1.05(size))))`).
  Source: https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/java/org/whispersystems/signalservice/internal/crypto/PaddingInputStream.java

### 1.2 Upload flow: upload forms, CDNs, resumable uploads

- The client asks the chat server for an upload form: `GET /v4/attachments/form/upload`. The server returns an `AttachmentDescriptorV3` with a **CDN number**, a server-generated **attachment key (object name)**, the **headers** to send, and a **signed upload location**.
  - CDN 2 = Google Cloud Storage; CDN 3 = a **TUS** (resumable) backend, chosen by experiment enrollment.
  - The server rate-limits by **count** and by **bytes** per account. If the declared `uploadLength` is over the configured maximum, it returns **HTTP 413**.
  Source: https://github.com/signalapp/Signal-Server/blob/main/service/src/main/java/org/whispersystems/textsecuregcm/controllers/AttachmentControllerV4.java
- The server only hands out a signed location. **The bytes go straight to the storage/CDN, not through the chat server**, and they are already encrypted.
- **Resumability:** the client saves a `ResumableUpload` spec locally: `secretKey`, `iv`, `cdnKey`, `cdnNumber`, `location`, `timeout`, `headers`. If the upload is interrupted (app restart, network loss), it resumes from that spec before the expiry.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/ResumableUploads.proto , https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/java/org/whispersystems/signalservice/internal/push/http/ResumableUploadSpec.kt
- **Re-use instead of re-upload:** `AttachmentUploadJob` skips uploading if the same attachment was uploaded less than **3 days** ago (`UPLOAD_REUSE_THRESHOLD = 3.days`) and still has a remote location. If a 400 comes back while fetching resumable-upload info, it clears the saved spec and starts over.
  Source: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentUploadJob.kt

### 1.3 The pointer inside the (E2EE) message

The message holds an `AttachmentPointer`, not the file. Its fields (from `SignalService.proto`):

| Field | Purpose |
|---|---|
| `cdnId` (1) / `cdnKey` (15), `cdnNumber` (14) | Where to download the ciphertext |
| `key` (3) | The per-attachment AES+HMAC key. It is only readable inside the E2EE message. |
| `digest` (6) | SHA-256 of the ciphertext, which lets the recipient detect tampering or a swapped file |
| `incrementalMac` (19), `chunkSize` (17) | Streaming integrity |
| `size` (4), `contentType` (2), `fileName` (7), `width`/`height` (9/10) | Metadata, also hidden from the server |
| `thumbnail` (5), `blurHash` (12) | Inline placeholder shown before download |
| `caption` (11), `flags` (8: voice note, borderless, GIF), `uploadTimestamp` (13), `clientUuid` (20) | UX and bookkeeping |

Source: https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto (`message AttachmentPointer`)

The server/CDN stores an opaque, padded blob under a random name. The file name, type, and key only exist inside the E2EE envelope.

### 1.4 Download and expiry

- The recipient fetches by `cdnNumber` + `cdnKey`/`cdnId`, then checks `digest` (and `incrementalMac` if present), then decrypts. On Android this runs in a background job.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/jobs/AttachmentDownloadJob.kt , https://github.com/signalapp/Signal-Desktop/blob/main/ts/AttachmentCrypto.node.ts (`decryptAttachmentV2`)
- **How long blobs stay on the server:** I could not find a first-party statement of the transit-CDN retention period. The support pages returned 403 to automated fetches, and the server repo does not expose the bucket lifecycle rules. The client's 3-day re-use window (above) suggests transit blobs are short-lived, but treat that as an inference. Separately, Signal's paid Secure Backups keep "the last 45 days of media" (per Signal Support search snippet: https://support.signal.org/hc/en-us/articles/9708267671322-Signal-Secure-Backups).

---

## 2. Link previews

### 2.1 Who fetches the URL

- **The sender's device fetches it. The server never does, and neither does the recipient.** The sender's app downloads the page's Open Graph metadata and image while composing and attaches the result to the message. Before sending, the user can remove a preview (tap "X") or turn previews off in Privacy settings.
  Source: https://signal.org/blog/i-link-therefore-i-am/
- Previews only work for **`https://`** links. Android's `LinkUtil.isValidPreviewUrl` requires the `https` scheme and rejects URLs with illegal or look-alike characters (RTL overrides, box-drawing chars, `..`/`…` in the domain).
  Sources: https://signal.org/blog/i-link-therefore-i-am/ , https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/util/LinkUtil.kt
- Parsing uses `og:*` meta tags, `article:*` tags, `<title>`, and favicon links.
  Source: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/linkpreview/LinkPreviewUtil.java
- **Hardening limits:**
  - Android caps text and images at **2 MB** each, disables the HTTP cache, sends the User-Agent `WhatsApp/2` (so sites serve OG tags), and checks redirects with an interceptor.
  - Desktop caps HTML at **~1 MB** and images at **~1 MB**, follows at most **20** redirects, and only accepts an allowlist of image MIME types.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/linkpreview/LinkPreviewRepository.java , https://github.com/signalapp/Signal-Desktop/blob/main/ts/linkPreviews/linkPreviewFetch.preload.ts
- Some Signal-internal links get special handling instead of a web fetch: sticker packs, group invite links, and call links.
  Source: LinkPreviewRepository.java (above)

### 2.2 Privacy tradeoffs: the proxy, then and now

- **2019 design (blog):** the app opened a TCP connection through a **privacy-enhancing proxy** that hid the user's IP from the site. TLS ran end-to-end from the app to the site, so "the Signal service never has access to the URL". Images were fetched with overlapping fixed-size range requests, so the proxy couldn't infer image sizes.
  Source: https://signal.org/blog/i-link-therefore-i-am/
- **Current code (observed on `main`, 2026-09):**
  - Android's `LinkPreviewRepository` builds its OkHttp client **without** the content-proxy selector.
  - `ContentProxySelector` still exists, but its allowlist contains only `giphy.com` and it throws for any other domain. It points at `contentproxy.signal.org:443`.
  - Desktop's `fetchForLinkPreviews` uses a direct HTTPS agent, or the user's own configured proxy if there is one. It does not use `contentProxyUrl`.
  - **Conclusion:** today the previewed site probably sees the **sender's IP** (TLS still keeps the URL away from Signal). I did not find a Signal announcement of this change, so treat it as a code observation, not an official statement.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/linkpreview/LinkPreviewRepository.java , https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/net/ContentProxySelector.java , https://github.com/signalapp/Signal-Android/blob/main/app/build.gradle.kts (`CONTENT_PROXY_HOST`), https://github.com/signalapp/Signal-Desktop/blob/main/ts/textsecure/WebAPI.preload.ts (`fetchForLinkPreviews`)
- Either way, the tradeoff Signal avoids is **server-side fetching**, which would expose every shared URL to the operator. The **recipient** never contacts the site, so a recipient can't be tracked by opening a message.

### 2.3 How the preview travels

The preview is part of the encrypted `DataMessage` as `Preview { url, title, image: AttachmentPointer, description, date }`. The thumbnail is uploaded and encrypted exactly like any other attachment.
Source: https://github.com/signalapp/Signal-Android/blob/main/lib/libsignal-service/src/main/protowire/SignalService.proto (`message Preview`)

---

## 3. View-once media

### 3.1 How it's enforced

- **Wire format:** `DataMessage.isViewOnce` (field 14) is a *flag*. The recipient's client is trusted to honour it.
  Source: SignalService.proto (above)
- **Sender side:** once sent, the sender cannot view it again. Android's `ViewOnceUtil.isViewable` returns `false` for outgoing view-once messages.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/revealable/ViewOnceUtil.java , https://signal.org/blog/view-once/
- **Recipient side, when opened:**
  - `ViewOnceMessageRepository` marks the message viewed (`setIncomingMessageViewed`), queues a viewed receipt, and syncs the "viewed" state to the user's other devices (`MultiDeviceViewedUpdateJob`).
  - There is also a `SyncMessage.ViewOnceOpen { senderAci, timestamp }`, so linked devices delete their copy too.
  - When the viewer screen stops (`onStop`), `ViewOnceMessageActivity` **deletes the decrypted blob** and closes. Leaving the app ends the viewing.
  - The chat keeps an empty "Viewed" placeholder.
  Sources: https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/revealable/ViewOnceMessageRepository.java , https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/revealable/ViewOnceMessageActivity.java , SignalService.proto (`message ViewOnceOpen`), https://signal.org/blog/view-once/ , https://github.com/signalapp/Signal-Desktop/blob/main/ts/messageModifiers/ViewOnceOpenSyncs.preload.ts
- **Unopened expiry:** Android treats a view-once message as "viewed" (gone) **30 days** after it was received (`MAX_LIFESPAN = 30 days`). Signal Support (via search snippet) says unopened view-once media is removed after **45 days**. These two sources disagree; the 30-day constant is the one in the Android code today.
  Sources: ViewOnceUtil.java (above), https://support.signal.org/hc/en-us/articles/360038443071-View-Once-Media
- View-once media is **never restored** from backups.
  Source: https://support.signal.org/hc/en-us/articles/360038443071-View-Once-Media (per search snippet; the page blocks automated fetch)

### 3.2 Limits

- **Screenshots and cameras:** Signal's view-once announcement doesn't promise screenshot prevention or screenshot notifications. It only covers not *storing* the media. Screenshot blocking is a separate, optional "Screen Security" setting (https://support.signal.org/hc/en-us/articles/360043469312-Screen-Security). On Android that uses the OS `FLAG_SECURE` window flag (https://developer.android.com/reference/android/view/WindowManager.LayoutParams#FLAG_SECURE). Nothing stops someone photographing the screen with another device.
  Source: https://signal.org/blog/view-once/
- **Trust model:** enforcement is **client-side**. A modified client could ignore `isViewOnce`. The E2EE guarantee only means the *server* can never see or keep the media: the server holds an encrypted blob plus a flag it can't read.

---

## 4. Node / Flutter equivalents for Convoze

### 4.1 Object storage and upload

- **S3 (or any S3-compatible store) presigned PUT:** the Node server signs a URL and the client uploads directly, with no AWS credentials. Same-key uploads overwrite. The SDK/CLI max expiry is **7 days**. The Content-Type must match what was signed.
  Source: https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html
  This is the same pattern as Signal's "upload form".
- **S3 Lifecycle expiration rules** can auto-delete transit blobs after N days.
  Source: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html
- **tus protocol:**
  - `POST` with `Upload-Length` creates the upload.
  - `HEAD` returns `Upload-Offset`.
  - `PATCH` with `Upload-Offset` resumes.
  - Every request carries the `Tus-Resumable` header.
  - The optional expiration extension sets `Upload-Expires`.
  Source: https://tus.io/protocols/resumable-upload
  This is what Signal's CDN 3 speaks.
- **Node tus server:** `@tus/server` + `@tus/s3-store` (S3 or S3-compatible). Requires Node >= 20.19.
  Sources: https://github.com/tus/tus-node-server , https://www.npmjs.com/package/@tus/s3-store

### 4.2 Flutter packages

- **Encryption:** `cryptography` (AES-GCM/CBC/CTR, ChaCha20-Poly1305, HMAC, SHA-2). Adding `cryptography_flutter` hands the work to Android/iOS OS APIs, which is much faster.
  Source: https://pub.dev/packages/cryptography
- **Uploads:** Dio, already chosen in ADR 0001, handles presigned PUT with progress and cancellation. For resumable uploads, pub.dev has tus clients: `tusc` (persistent cache that survives restarts), `tus_client`, and `another_tus_client`. Check maintenance status before choosing one.
  Sources: https://pub.dev/packages/tusc , https://pub.dev/documentation/tus_client/latest/ , https://pub.dev/packages/another_tus_client
- **Screen protection for view-once:** `screen_protector` uses FLAG_SECURE-style blocking on Android. On iOS it offers screenshot prevention, background blur/colour overlays, and `isRecording()` detection.
  Source: https://pub.dev/packages/screen_protector

---

## Summary

- **Attachments (Signal):** encrypt on the client with a fresh per-file key (AES-256-CBC + HMAC-SHA256, padded size) → ask the server for a short-lived signed upload form (GCS or tus CDN) → upload the ciphertext straight to the CDN → send an `AttachmentPointer` (CDN location + key + digest + metadata) inside the E2EE message → recipient downloads, checks the digest, decrypts. The server only sees rate-limited, size-padded, opaque blobs.
- **Link previews (Signal):** built on the sender's device (https only, OG tags, size and redirect caps). They travel inside the encrypted message as `Preview` + an attachment thumbnail. The recipient never fetches the URL. The proxy that hid the sender's IP in 2019 no longer appears to be used for general previews in current client code.
- **View-once (Signal):** a flag honoured by clients. The sender can't re-open it; the recipient's decrypted copy is deleted when the viewer closes; the "viewed" state is synced to linked devices; unopened media expires (30 days in Android code, 45 in support docs). Screenshots aren't blocked by view-once itself, and the guarantee depends on honest clients.

## Recommendations for Convoze

Convoze is not E2EE today (Node/Socket.IO/Postgres with server-readable messages). So copy Signal's *architecture*, not its crypto guarantees.

1. **Replace the planned `multer`-to-disk path with direct-to-storage uploads.**
   - Add `POST /media/upload-url`. It checks auth, MIME allowlist, a declared size cap, and per-user count/byte rate limits (like Signal's 413 + rate limiters).
   - The server generates a random object key and returns a **presigned S3 PUT** URL. Use an S3-compatible store (AWS S3, Cloudflare R2, or MinIO in dev).
   - The client uploads with Dio, then sends a chat message with a small **attachment pointer**: `{objectKey, contentType, size, width, height, blurHash/thumbnail, caption}`. Never send raw bytes over Socket.IO.
   - Keep ADR 0001's Dio choice. Nothing new is needed.
2. **Add resumable uploads later.** When videos or large files need it, put `@tus/server` + `@tus/s3-store` behind the same auth and use a Dart tus client (`tusc`). Don't build this for v1.
3. **Downloads:** serve through short-lived **presigned GET** URLs, not a public bucket. Keep a server-side SHA-256 or ETag check. Set an S3 Lifecycle rule only if you choose to make media ephemeral. Unlike Signal, Convoze's server *is* the message history, so media should normally live as long as the message.
4. **Optional, cheap hardening borrowed from Signal:** encrypt each file on the client with a random key (`cryptography` + `cryptography_flutter`, AES-GCM) and store the key in the message row. This does *not* hide files from the server, since the server stores the key too. It does make a leaked bucket useless without the DB. Only worth doing if Convoze moves toward E2EE later; otherwise rely on bucket privacy + presigned URLs.
5. **Link previews: generate them on the sender's device, not on the server.** This follows Signal's model and avoids SSRF risk and URL logging on the Node server.
   - https only; parse `og:*`/`<title>`; ~1–2 MB caps; limit redirects; reject IP-literal/local hosts.
   - Upload the thumbnail through the same media pipeline and attach `{url, title, description, imageObjectKey}` to the message. Add a per-message "remove preview" control and a global toggle.
   - Say plainly in-app that the sender's IP is visible to the linked site, which is also true of Signal's current clients.
6. **View-once: build as a best-effort feature and label it honestly.**
   - Store an `isViewOnce` flag.
   - On first open, the server records `viewedAt`, **deletes the object from storage** (enforcement Convoze *can* do on the server, which Signal can't) and stops issuing GET URLs.
   - The client shows the media in a dedicated screen with `screen_protector` enabled, clears any cached file when the screen closes, and syncs "viewed" over Socket.IO.
   - Unopened items expire after 30 days via a cron job or Lifecycle rule.
   - Tell users screenshots or another camera can still capture the media, and (without E2EE) the operator can technically see it before it's viewed.
7. **Rank for the #10 map:** attachments via presigned uploads = **high** (core feature #9, and it makes the media design solid). Sender-side link previews = **medium**. View-once = **low/nice-to-have** (little value without E2EE, and its guarantee is weak).
