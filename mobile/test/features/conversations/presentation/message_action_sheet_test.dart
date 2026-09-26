import 'package:convoze/features/conversations/data/chat_message_view.dart';
import 'package:convoze/features/conversations/presentation/message_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessageView _message({
  String id = 'msg-1',
  String type = 'text',
  String? content = 'hello',
  bool fromMe = true,
  bool isDeleted = false,
  MessageTick? tick = MessageTick.sent,
}) => ChatMessageView(
  id: id,
  clientMsgId: 'c1',
  senderId: fromMe ? 'me' : 'other',
  fromMe: fromMe,
  content: content,
  type: type,
  isDeleted: isDeleted,
  createdAt: DateTime.utc(2026, 1, 1),
  tick: tick,
);

Future<void> openSheet(
  WidgetTester tester,
  ChatMessageView message, {
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showMessageActions(context, message: message, onEdit: onEdit, onDelete: onDelete),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offers Edit and Delete for the sender\'s own landed text message', (tester) async {
    await openSheet(tester, _message());
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('offers neither for someone else\'s message', (tester) async {
    await openSheet(tester, _message(fromMe: false, tick: null));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('offers neither for a media message', (tester) async {
    await openSheet(tester, _message(type: 'image', content: ''));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('offers neither for a still-pending Outbox row', (tester) async {
    await openSheet(tester, _message(tick: MessageTick.clock));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('offers neither for a failed Outbox row', (tester) async {
    await openSheet(tester, _message(tick: MessageTick.failed));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('offers neither for an already-deleted message', (tester) async {
    await openSheet(tester, _message(isDeleted: true, content: null, tick: null));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('tapping Edit pops the sheet and calls onEdit', (tester) async {
    var edited = false;
    await openSheet(tester, _message(), onEdit: () => edited = true);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(edited, isTrue);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('tapping Delete pops the sheet and calls onDelete', (tester) async {
    var deleted = false;
    await openSheet(tester, _message(), onDelete: () => deleted = true);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(find.text('Delete'), findsNothing);
  });
}
