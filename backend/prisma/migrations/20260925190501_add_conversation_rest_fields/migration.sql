-- AlterTable
ALTER TABLE "Conversation" ADD COLUMN     "createdById" UUID;

-- AlterTable
ALTER TABLE "Participant" ADD COLUMN     "leftAt" TIMESTAMPTZ(3);
