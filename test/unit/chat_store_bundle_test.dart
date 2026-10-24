import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/chat_store.dart';

/// v1.38.1 — SessionBundle round-trip: ONE decode must restore messages,
/// active modules, the setup-wait flag and the latest plan together.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_bundle_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ChatStore store() =>
      ChatStore(resolveBaseDir: () async => tempDir, offloadIsolate: false);

  test('loadBundle restores everything from a single read', () async {
    final ChatStore st = store();
    const String id = 'session-bundle-1';
    await st.save(
      id: id,
      title: 'Bundle test',
      messages: <ChatMessage>[
        ChatMessage.user('halo'),
        ChatMessage.assistant('halo juga'),
      ],
      modules: <String>['onhomeroom-daily', 'counter'],
      waitingForSetup: true,
      todos: const <TodoItem>[
        TodoItem(content: 'step one', status: TodoStatus.completed),
        TodoItem(content: 'step two', status: TodoStatus.inProgress),
      ],
    );

    final SessionBundle? bundle = await st.loadBundle(id);
    expect(bundle, isNotNull);
    expect(bundle!.messages, hasLength(2));
    expect(bundle.messages.first.role, Role.user);
    expect(bundle.messages.first.content, 'halo');
    expect(bundle.messages.last.content, 'halo juga');
    expect(bundle.modules, <String>['onhomeroom-daily', 'counter']);
    expect(bundle.waitingForSetup, isTrue);
    expect(bundle.todos, hasLength(2));
    expect(bundle.todos.first.status, TodoStatus.completed);
    expect(bundle.todos.last.status, TodoStatus.inProgress);
  });

  test('loadBundle of a missing session yields null', () async {
    final SessionBundle? bundle = await store().loadBundle('does-not-exist');
    expect(bundle, isNull);
  });

  test('loadBundle tolerates a corrupted file', () async {
    final Directory chats = Directory('${tempDir.path}/chats');
    chats.createSync(recursive: true);
    File('${chats.path}/broken.json').writeAsStringSync('{not json');
    final SessionBundle? bundle = await store().loadBundle('broken');
    expect(bundle, isNull);
  });

  test(
    'loadBundle of a session saved without extras yields defaults',
    () async {
      final ChatStore st = store();
      const String id = 'session-bundle-2';
      await st.save(
        id: id,
        title: 'Minimal',
        messages: <ChatMessage>[ChatMessage.user('ping')],
      );
      final SessionBundle? bundle = await st.loadBundle(id);
      expect(bundle, isNotNull);
      expect(bundle!.messages, hasLength(1));
      expect(bundle.modules, isEmpty);
      expect(bundle.waitingForSetup, isFalse);
      expect(bundle.todos, isEmpty);
    },
  );
}
