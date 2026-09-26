-- AlterTable
ALTER TABLE "Participant" ADD COLUMN     "archivedAt" TIMESTAMPTZ(3),
ADD COLUMN     "hiddenAt" TIMESTAMPTZ(3),
ADD COLUMN     "historyClearedMessageId" UUID,
ADD COLUMN     "mutedUntil" TIMESTAMPTZ(3),
ADD COLUMN     "pinnedAt" TIMESTAMPTZ(3);

-- AddForeignKey
ALTER TABLE "Participant" ADD CONSTRAINT "Participant_historyClearedMessageId_fkey" FOREIGN KEY ("historyClearedMessageId") REFERENCES "Message"("id") ON DELETE SET NULL ON UPDATE CASCADE;
