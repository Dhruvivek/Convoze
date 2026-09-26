-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "MessageType" ADD VALUE 'image';
ALTER TYPE "MessageType" ADD VALUE 'file';

-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "mediaBytes" INTEGER,
ADD COLUMN     "mediaFileName" VARCHAR(255),
ADD COLUMN     "mediaFormat" TEXT,
ADD COLUMN     "mediaHeight" INTEGER,
ADD COLUMN     "mediaPublicId" VARCHAR(255),
ADD COLUMN     "mediaResourceType" TEXT,
ADD COLUMN     "mediaWidth" INTEGER;
