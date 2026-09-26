import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'typing_repository.dart';

part 'typers_providers.g.dart';

@Riverpod(keepAlive: true)
Stream<Map<String, Set<String>>> typersMap(Ref ref) =>
    ref.watch(typingRepositoryProvider).changes;

/// Who is currently typing in [conversationId] (#35) — the future chat
/// screen's header/message list just watches this; rendering it is out of
/// scope here.
@riverpod
Set<String> typers(Ref ref, String conversationId) =>
    (ref.watch(typersMapProvider).value ?? const {})[conversationId] ?? const {};
