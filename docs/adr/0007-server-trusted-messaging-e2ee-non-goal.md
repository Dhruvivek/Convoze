# Server-trusted messaging; E2EE a non-goal

**Status:** accepted

## Context

The Signal study map (#10) put end-to-end encryption up as an open question, and #11 researched what it would take on Convoze's stack. Issue #16 decides go/no-go and scope. Convoze's existing decisions all assume the server can read message content: server-side search and reporting are firm requirements from `docs/features.md` via #1, media relies on Cloudinary transforms and upload-preset validation (ADR 0002), sessions are multi-device (ADR 0003), and push carries preview text (ADR 0006).

## Decision

Convoze is **server-trusted by design**: the Node backend can read message content and media, and end-to-end encryption is a deliberate non-goal — not in v1 and not scoped as a post-MVP feature. No seams are pre-built for it. It can only return via a later ADR that supersedes this one.

Reasons:

- **No supported Flutter route.** libsignal's official bindings are Java, Swift and TypeScript only, and use outside Signal is unsupported with no API stability. The Dart port (`libsignal_protocol_dart`) is maintained but has no PQXDH and no published audit.
- **License conflict.** libsignal is AGPL-3.0 and the Dart port GPL-3.0; Convoze is MIT.
- **Conflicts with settled decisions.** Per-device E2EE sessions contradict the multi-device `Session` model (ADR 0003) unless every message is fanned out per recipient Device; server-side search and content-bearing reports (firm requirements) stop working; Cloudinary can't transform or validate encrypted blobs (ADR 0002); push can't carry previews (ADR 0006).
- **Cost vs. value.** Even 1:1-only Signal-style E2EE is ~1–2 weeks with real silent-decrypt-failure risk; a quick static-key version (~2–3 days) has no forward secrecy and loses history on reinstall — weak crypto that's worse to defend than none.

## Considered options

- **1:1-only E2EE in v1** — rejected for the reasons above.
- **No-go for v1 with a committed post-MVP "secret chat"** (#11's fallback: opt-in, 1:1, single device) — rejected because committing to it pressures paid-for seams now (e.g. client-encrypted attachments, forfeiting ADR 0002's transforms) for a feature that may never ship, and its single-device constraint contradicts ADR 0003.

## Consequences

- #10's "client-encrypted attachments" pick is dropped; ADR 0002 stands. Its "uploaded separately, pointer in message" half is already how ADR 0002 works.
- #10's "content-free push" pick is deferred, not adopted; ADR 0006 stands, and its `buildPush()` seam covers a later switch.
- `docs/features.md` features (search, reporting/blocking, media, edit/delete, reactions, read watermarks) keep their server-side designs unchanged.
- User-facing copy (app, README, store listing) claims only "encrypted in transit (TLS)" — never "encrypted chats" or "private messages". Encrypting the local client DB at rest (#18) is a separate threat model and unaffected.
- Reversing this later means, at minimum: a prekey/identity-key API, per-Device key fan-out, local-only search, content-free push, client-encrypted media without Cloudinary transforms, and content-free reports.
