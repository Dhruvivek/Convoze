import 'package:convoze/features/conversations/data/local_chat_message.dart';
import 'package:convoze/features/conversations/presentation/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LocalChatMessage _message({
  String type = 'text',
  String? content = 'hello',
  bool senderIsMe = true,
  bool isPending = false,
  bool isFailed = false,
  String? mediaFileName,
  int? mediaBytes,
  String? mediaThumbnailUrl,
  DateTime? editedAt,
}) => LocalChatMessage(
  clientMsgId: 'c1',
  senderIsMe: senderIsMe,
  content: content,
  type: type,
  isDeleted: false,
  createdAt: DateTime.utc(2026, 1, 1),
  editedAt: editedAt,
  isPending: isPending,
  isFailed: isFailed,
  mediaFileName: mediaFileName,
  mediaBytes: mediaBytes,
  mediaThumbnailUrl: mediaThumbnailUrl,
);

Future<void> pump(WidgetTester tester, LocalChatMessage message) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: MessageBubble(message: message)),
    ),
  ),
);

void main() {
  testWidgets('renders a text message', (tester) async {
    await pump(tester, _message(content: 'hi there'));
    expect(find.text('hi there'), findsOneWidget);
  });

  testWidgets('renders a document bubble with its name and size', (tester) async {
    await pump(
      tester,
      _message(type: 'file', content: '', mediaFileName: 'invoice.pdf', mediaBytes: 2048),
    );
    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(find.text('2 KB'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file_outlined), findsOneWidget);
  });

  testWidgets('renders an image caption under the thumbnail', (tester) async {
    await pump(tester, _message(type: 'image', content: 'nice view'));
    expect(find.text('nice view'), findsOneWidget);
  });

  testWidgets('a pending message dims and shows a clock icon', (tester) async {
    await pump(tester, _message(isPending: true));
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });

  testWidgets('a failed message shows an error icon', (tester) async {
    await pump(tester, _message(isFailed: true));
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('an edited message shows an (edited) label', (tester) async {
    await pump(tester, _message(editedAt: DateTime.utc(2026, 1, 1, 12)));
    expect(find.text('(edited)'), findsOneWidget);
  });

  testWidgets('an unedited message shows no (edited) label', (tester) async {
    await pump(tester, _message());
    expect(find.text('(edited)'), findsNothing);
  });
}
