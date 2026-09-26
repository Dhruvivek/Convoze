import 'package:convoze/core/db/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('outboxCount', () {
    test('is 0 with an empty Outbox', () async {
      expect(await db.outboxCount(), 0);
    });

    test('counts every row regardless of status', () async {
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c1',
          conversationId: 'conv-1',
          content: 'hi',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c2',
          conversationId: 'conv-1',
          content: 'failed one',
          status: const Value('failed'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect(await db.outboxCount(), 2);
    });
  });

  group('wipeAll', () {
    test('clears the Outbox along with everything wipeExceptOutbox clears (#54)', () async {
      await db.into(db.users).insert(
        UsersCompanion.insert(id: 'u1', phoneNumber: '+14155550100'),
      );
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c1',
          conversationId: 'conv-1',
          content: 'unsent',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      await db.wipeAll();

      expect(await db.select(db.users).get(), isEmpty);
      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });
}
