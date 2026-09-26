import { deliveryUrls } from '../media/cloudinarySigner.js';

// A Message's wire shape, shared by the Hydrator (#47) and the REST history
// pages (#50). A deleted Message never carries its content past this
// boundary, even if the caller reused a stale row: a tombstone is always
// built from scratch.
export function tombstone(message) {
  return { id: message.id, conversationId: message.conversationId, isDeleted: true };
}

// A media message's URL is signed fresh here, never stored (#40), so every
// read path — sync batches, history pages, list previews — goes through
// this one function rather than each inventing its own signing.
// `deliveryUrls` is a pure local URL construction (no Cloudinary API call),
// so this stays synchronous like every other call site already expects.
export function messagePayload(message) {
  if (message.isDeleted) return tombstone(message);
  const payload = {
    id: message.id,
    conversationId: message.conversationId,
    senderId: message.senderId,
    clientMsgId: message.clientMsgId,
    replyToMessageId: message.replyToMessageId,
    linkPreview: message.linkPreview,
    type: message.type,
    content: message.content,
    createdAt: message.createdAt,
    editedAt: message.editedAt,
    isDeleted: message.isDeleted,
  };
  if (message.type !== 'text' && message.mediaPublicId) {
    const { url, thumbnailUrl } = deliveryUrls({
      publicId: message.mediaPublicId,
      resourceType: message.mediaResourceType,
    });
    payload.mediaPublicId = message.mediaPublicId;
    payload.mediaResourceType = message.mediaResourceType;
    payload.mediaBytes = message.mediaBytes;
    payload.mediaWidth = message.mediaWidth;
    payload.mediaHeight = message.mediaHeight;
    payload.mediaFormat = message.mediaFormat;
    payload.mediaFileName = message.mediaFileName;
    payload.mediaUrl = url;
    payload.mediaThumbnailUrl = thumbnailUrl;
  }
  return payload;
}
