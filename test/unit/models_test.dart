import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/models/models.dart';

void main() {
  group('ProviderPreset', () {
    test('json roundtrip preserves every field', () {
      const ProviderPreset preset = ProviderPreset(
        id: 'p1',
        name: 'InferHub',
        baseUrl: 'https://api.inferhub.dev/v1',
        apiKey: 'sk-airo-test',
        model: 'glm-4.6',
        modelsCache: <String>['glm-4.6', 'glm-4.5-air'],
      );
      final ProviderPreset decoded = ProviderPreset.fromJson(preset.toJson());
      expect(decoded.id, 'p1');
      expect(decoded.name, 'InferHub');
      expect(decoded.baseUrl, 'https://api.inferhub.dev/v1');
      expect(decoded.apiKey, 'sk-airo-test');
      expect(decoded.model, 'glm-4.6');
      expect(decoded.hasKey, isTrue);
      expect(decoded.hasModelsCache, isTrue);
      expect(decoded.modelsCache, <String>['glm-4.6', 'glm-4.5-air']);
    });

    test('hasKey is false for blank keys', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      expect(preset.hasKey, isFalse);
    });

    test('modelsCache defaults to empty and tolerates missing json field', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      expect(preset.modelsCache, isEmpty);
      expect(preset.hasModelsCache, isFalse);
      final ProviderPreset decoded = ProviderPreset.fromJson(<String, dynamic>{
        'id': 'p',
        'name': 'X',
      });
      expect(decoded.modelsCache, isEmpty);
    });

    test('copyWith modelsCache replaces the cached list', () {
      const ProviderPreset preset = ProviderPreset(id: 'p', name: 'X');
      final ProviderPreset cached = preset.copyWith(
        modelsCache: <String>['a/b'],
      );
      expect(cached.modelsCache, <String>['a/b']);
      expect(preset.modelsCache, isEmpty);
    });
  });

  group('presetHostLabel', () {
    test('reduces a base URL to its host', () {
      expect(
        presetHostLabel('https://api.inferhub.dev/v1'),
        'api.inferhub.dev',
      );
      expect(presetHostLabel('https://openrouter.ai/api/v1'), 'openrouter.ai');
    });

    test('falls back to the raw value when parsing fails', () {
      expect(presetHostLabel('not a url'), 'not a url');
      expect(presetHostLabel(''), '');
    });
  });

  group('AppSettings preset migration', () {
    test('fresh settings seed all built-in presets without keys', () {
      final AppSettings settings = AppSettings();
      expect(
        settings.presets.map((p) => p.name),
        containsAll(<String>['OpenRouter', 'InferHub', 'Z.AI', 'Custom']),
      );
      expect(settings.presets.every((p) => !p.hasKey), isTrue);
    });

    test('legacy storage (no presets) migrates the active key into the '
        'matching preset', () {
      final AppSettings migrated = AppSettings.fromJson(<String, dynamic>{
        'providerName': 'InferHub',
        'baseUrl': 'https://api.inferhub.dev/v1',
        'apiKey': 'sk-airo-legacy',
        'model': 'glm-4.6',
      });
      final ProviderPreset inferhub = migrated.presets.singleWhere(
        (p) => p.name == 'InferHub',
      );
      expect(inferhub.apiKey, 'sk-airo-legacy');
      expect(inferhub.model, 'glm-4.6');
      expect(inferhub.baseUrl, 'https://api.inferhub.dev/v1');
      // Other presets stay empty and the active connection is untouched.
      expect(migrated.apiKey, 'sk-airo-legacy');
      expect(
        migrated.presets.singleWhere((p) => p.name == 'OpenRouter').hasKey,
        isFalse,
      );
    });

    test('custom presets survive migration roundtrip', () {
      final AppSettings original = AppSettings(
        providerName: 'Custom',
        baseUrl: 'https://my.host/v1',
        apiKey: 'sk-custom',
        presets: <ProviderPreset>[
          const ProviderPreset(id: 'c1', name: 'Custom', baseUrl: ''),
          const ProviderPreset(
            id: 'c2',
            name: 'Mine',
            baseUrl: 'https://my.host/v1',
            apiKey: 'sk-custom',
          ),
        ],
      );
      final AppSettings decoded = AppSettings.fromJson(original.toJson());
      expect(decoded.presets.any((p) => p.name == 'Mine'), isTrue);
      expect(
        decoded.presets.singleWhere((p) => p.name == 'Mine').apiKey,
        'sk-custom',
      );
    });
  });

  group('theme mode setting', () {
    test('defaults to dark and parses valid names', () {
      expect(themeModeSettingFromName(null), ThemeModeSetting.dark);
      expect(themeModeSettingFromName('light'), ThemeModeSetting.light);
      expect(themeModeSettingFromName('system'), ThemeModeSetting.system);
      expect(themeModeSettingFromName('bogus'), ThemeModeSetting.dark);
    });
  });

  group('maxSteps bounds', () {
    test('clamps slider/input values into 1..100', () {
      expect(clampMaxSteps(0), 1);
      expect(clampMaxSteps(-5), 1);
      expect(clampMaxSteps(1), 1);
      expect(clampMaxSteps(42), 42);
      expect(clampMaxSteps(100), 100);
      expect(clampMaxSteps(1000), 100);
      expect(clampMaxSteps('77'), 77);
      expect(clampMaxSteps('abc'), 1);
    });

    test('copyWith clamps out-of-range values', () {
      final AppSettings settings = AppSettings().copyWith(maxSteps: 5000);
      expect(settings.maxSteps, 100);
    });

    test('json storage clamps corrupted values', () {
      final AppSettings settings = AppSettings.fromJson(<String, dynamic>{
        'maxSteps': 99999,
      });
      expect(settings.maxSteps, 100);
    });
  });

  group('run until done', () {
    test('defaults to true so the agent works until tasks finish', () {
      expect(AppSettings().runUntilDone, isTrue);
    });

    test('json roundtrip preserves the flag', () {
      final AppSettings off = AppSettings(runUntilDone: false);
      final AppSettings decoded = AppSettings.fromJson(off.toJson());
      expect(decoded.runUntilDone, isFalse);
      expect(decoded.maxSteps, off.maxSteps);
    });

    test('legacy storage without the flag falls back to true (backward '
        'compatible)', () {
      final AppSettings decoded = AppSettings.fromJson(<String, dynamic>{
        'apiKey': 'k',
        'maxSteps': 6,
      });
      expect(decoded.runUntilDone, isTrue);
    });

    test('copyWith toggles the flag without touching maxSteps', () {
      final AppSettings settings = AppSettings(maxSteps: 42);
      final AppSettings off = settings.copyWith(runUntilDone: false);
      expect(off.runUntilDone, isFalse);
      expect(off.maxSteps, 42);
      final AppSettings backOn = off.copyWith(runUntilDone: true);
      expect(backOn.runUntilDone, isTrue);
    });

    test('unboundedStepLimit stays far beyond any real task', () {
      expect(unboundedStepLimit, greaterThan(maxMaxSteps));
      expect(unboundedStepLimit, greaterThanOrEqualTo(10000));
    });
  });

  group('attachment kinds', () {
    test('images, text and binaries are classified by extension', () {
      expect(attachmentKindFor('photo.PNG'), AttachmentKind.image);
      expect(attachmentKindFor('scan.jpeg'), AttachmentKind.image);
      expect(attachmentKindFor('notes.md'), AttachmentKind.text);
      expect(attachmentKindFor('data.json'), AttachmentKind.text);
      expect(attachmentKindFor('script.dart'), AttachmentKind.text);
      expect(attachmentKindFor('report.pdf'), AttachmentKind.other);
      expect(attachmentKindFor('archive.zip'), AttachmentKind.other);
      expect(attachmentKindFor('noext'), AttachmentKind.other);
    });
  });

  group('ChatAttachment', () {
    test('json roundtrip', () {
      const ChatAttachment att = ChatAttachment(
        name: 'a.png',
        path: '/tmp/a.png',
        sizeBytes: 12,
        kind: AttachmentKind.image,
      );
      final ChatAttachment decoded = ChatAttachment.fromJson(att.toJson());
      expect(decoded.name, 'a.png');
      expect(decoded.kind, AttachmentKind.image);
      expect(decoded.sizeBytes, 12);
    });

    test('malformed json degrades to safe defaults', () {
      final ChatAttachment att = ChatAttachment.fromJson(<String, dynamic>{});
      expect(att.kind, AttachmentKind.other);
      expect(att.name, 'file');
    });
  });

  group('ContextEntry', () {
    test('json roundtrip', () {
      const ContextEntry entry = ContextEntry(
        id: 'c1',
        name: 'Rules',
        content: 'Be brief',
        enabled: true,
      );
      final ContextEntry decoded = ContextEntry.fromJson(entry.toJson());
      expect(decoded.id, 'c1');
      expect(decoded.enabled, isTrue);
      expect(decoded.content, 'Be brief');
    });
  });

  group('ChatMessage attachments', () {
    test('json roundtrip keeps attachments', () {
      final ChatMessage message = ChatMessage.user(
        'hello',
        attachments: <ChatAttachment>[
          const ChatAttachment(
            name: 'x.txt',
            path: '/x',
            sizeBytes: 3,
            kind: AttachmentKind.text,
          ),
        ],
      );
      final ChatMessage decoded = ChatMessage.fromJson(message.toJson());
      expect(decoded.attachments, hasLength(1));
      expect(decoded.attachments.first.name, 'x.txt');
    });
  });

  group('todo plan (plan-first)', () {
    test('planFirst defaults to true', () {
      expect(AppSettings().planFirst, isTrue);
    });

    test('planFirst roundtrip + backward compatible default', () {
      final AppSettings off = AppSettings(planFirst: false);
      expect(AppSettings.fromJson(off.toJson()).planFirst, isFalse);
      expect(
        AppSettings.fromJson(<String, dynamic>{'apiKey': 'k'}).planFirst,
        isTrue,
        reason: 'legacy storage without the flag must keep plan-first on',
      );
      expect(off.copyWith(planFirst: true).planFirst, isTrue);
    });

    test('todoStatusFromName accepts wire and dart spellings', () {
      expect(todoStatusFromName('pending'), TodoStatus.pending);
      expect(todoStatusFromName('in_progress'), TodoStatus.inProgress);
      expect(todoStatusFromName('inProgress'), TodoStatus.inProgress);
      expect(todoStatusFromName('completed'), TodoStatus.completed);
      expect(todoStatusFromName('done'), TodoStatus.completed);
      expect(todoStatusFromName('weird'), TodoStatus.pending);
      expect(todoStatusFromName(null), TodoStatus.pending);
    });

    test('parseTodoList validates, trims and normalizes entries', () {
      final List<TodoItem> todos = parseTodoList(<dynamic>[
        <String, dynamic>{'content': '  research  ', 'status': 'in_progress'},
        <String, dynamic>{'content': 'write report', 'status': 'completed'},
        <String, dynamic>{'text': 'legacy key works', 'status': 'pending'},
        <String, dynamic>{'content': '', 'status': 'pending'},
        <String, dynamic>{'status': 'pending'},
        'junk',
        <String, dynamic>{'content': 'odd status', 'status': 'nonsense'},
      ]);
      expect(todos, hasLength(4));
      expect(todos[0].content, 'research');
      expect(todos[0].status, TodoStatus.inProgress);
      expect(todos[1].status, TodoStatus.completed);
      expect(todos[2].content, 'legacy key works');
      expect(todos[3].content, 'odd status');
      expect(todos[3].status, TodoStatus.pending);
    });

    test('parseTodoList rejects non-list input and caps the size', () {
      expect(parseTodoList(null), isEmpty);
      expect(parseTodoList('nope'), isEmpty);
      expect(parseTodoList(<String, dynamic>{'content': 'x'}), isEmpty);
      final List<dynamic> oversized = <dynamic>[
        for (var i = 0; i < maxTodoItems + 10; i++)
          <String, dynamic>{'content': 't$i', 'status': 'pending'},
      ];
      expect(parseTodoList(oversized), hasLength(maxTodoItems));
    });

    test('hasIncompleteTodos detects unfinished plans', () {
      expect(hasIncompleteTodos(const <TodoItem>[]), isFalse);
      expect(
        hasIncompleteTodos(<TodoItem>[
          const TodoItem(content: 'a', status: TodoStatus.completed),
        ]),
        isFalse,
      );
      expect(
        hasIncompleteTodos(<TodoItem>[
          const TodoItem(content: 'a', status: TodoStatus.completed),
          const TodoItem(content: 'b', status: TodoStatus.inProgress),
        ]),
        isTrue,
      );
    });

    test('TodoItem json roundtrip keeps the wire status spelling', () {
      const TodoItem item = TodoItem(
        content: 'x',
        status: TodoStatus.inProgress,
      );
      expect(item.toJson()['status'], 'in_progress');
      final TodoItem decoded = TodoItem.fromJson(item.toJson());
      expect(decoded.status, TodoStatus.inProgress);
      expect(decoded.content, 'x');
    });
  });

  group('random user-agent prompt (askRandomUa)', () {
    test('askRandomUa defaults to true', () {
      expect(AppSettings().askRandomUa, isTrue);
    });

    test('askRandomUa roundtrip + backward compatible default', () {
      final AppSettings off = AppSettings(askRandomUa: false);
      expect(AppSettings.fromJson(off.toJson()).askRandomUa, isFalse);
      expect(
        AppSettings.fromJson(<String, dynamic>{'apiKey': 'k'}).askRandomUa,
        isTrue,
        reason: 'legacy storage without the flag must keep the prompt on',
      );
      expect(off.copyWith(askRandomUa: true).askRandomUa, isTrue);
    });
  });

  group('device commands master switch (v1.31.0)', () {
    test('defaults to OFF — module shell commands are opt-in', () {
      expect(AppSettings().deviceCommandsEnabled, isFalse);
    });

    test('legacy storage without the flag stays off (safe default)', () {
      expect(
        AppSettings.fromJson(<String, dynamic>{'apiKey': 'k'})
            .deviceCommandsEnabled,
        isFalse,
      );
    });

    test('roundtrip + copyWith persist the toggle', () {
      final AppSettings on = AppSettings().copyWith(
        deviceCommandsEnabled: true,
      );
      expect(on.deviceCommandsEnabled, isTrue);
      expect(AppSettings.fromJson(on.toJson()).deviceCommandsEnabled, isTrue);
      final AppSettings off = AppSettings(deviceCommandsEnabled: true)
          .copyWith(deviceCommandsEnabled: false);
      expect(AppSettings.fromJson(off.toJson()).deviceCommandsEnabled, isFalse);
    });
  });

  group('ToolCall argument redaction (v1.41.0)', () {
    test('credential-looking keys never reach the transcript', () {
      final ToolCall call = ToolCall(
        id: 't1',
        name: 'http_request',
        arguments: <String, dynamic>{
          'url': 'https://api.example.com/v1/orders',
          'api_key': 'sk-live-SECRET',
          'headers': <String, dynamic>{
            'Authorization': 'Bearer SECRET',
            'Accept': 'application/json',
          },
          'items': <dynamic>[
            <String, dynamic>{'token': 'SECRET', 'sku': 'A1'},
          ],
        },
      );
      final Map<String, dynamic> safe = call.safeArguments;
      expect(safe['url'], 'https://api.example.com/v1/orders');
      expect(safe['api_key'], '<redacted>');
      final Map<String, dynamic> headers =
          safe['headers'] as Map<String, dynamic>;
      expect(headers['Authorization'], '<redacted>');
      expect(headers['Accept'], 'application/json');
      final List<dynamic> items = safe['items'] as List<dynamic>;
      expect((items.single as Map<String, dynamic>)['token'], '<redacted>');
      expect((items.single as Map<String, dynamic>)['sku'], 'A1');
      // The persisted JSON is redacted too — the chat file is the leak.
      expect(jsonEncode(call.toJson()), isNot(contains('SECRET')));
      // The live call keeps its arguments: the tool still has to run.
      expect(call.arguments['api_key'], 'sk-live-SECRET');
    });

    test('browser_type never renders or persists typed text', () {
      final ToolCall call = ToolCall(
        id: 't2',
        name: 'browser_type',
        arguments: <String, dynamic>{
          'text': 'correct horse battery staple',
          'selector': '#passphrase',
        },
      );
      expect(call.argsSummary, '•••• (28 chars)');
      expect(call.safeArguments['text'], '<redacted>');
      expect(jsonEncode(call.toJson()), isNot(contains('battery')));
    });

    test('unknown tools redact secret keys in the UI summary', () {
      final ToolCall call = ToolCall(
        id: 't3',
        name: 'some_future_tool',
        arguments: <String, dynamic>{
          'password': 'hunter2',
          'account': 'alice',
        },
      );
      expect(call.argsSummary, 'password: <redacted>, account: alice');
    });

    test('skill_config keeps only key names', () {
      final ToolCall call = ToolCall(
        id: 't4',
        name: 'skill_config',
        arguments: <String, dynamic>{
          'name': 'wallet',
          'values': <String, dynamic>{'API_KEY': 'SECRET', 'NETWORK': 'bsc'},
        },
      );
      final Map<String, dynamic> safe = call.safeArguments;
      expect(safe['name'], 'wallet');
      expect(
        (safe['values'] as Map<String, dynamic>).keys,
        containsAll(<String>['API_KEY', 'NETWORK']),
      );
      expect(jsonEncode(safe), isNot(contains('SECRET')));
    });
  });
}
