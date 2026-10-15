import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/services/module_registry.dart';
import 'package:zagents/ui/screens/modules_screen.dart';

import '../support/test_doubles.dart';

/// In-memory ModuleRegistry test double: no disk IO inside the async test
/// zone, records every mutation for assertions.
class ScriptedModuleRegistry extends ModuleRegistry {
  ScriptedModuleRegistry()
    : super(resolveBaseDir: () async => Directory.systemTemp);

  final Map<String, ChatModule> modules = <String, ChatModule>{};
  final List<String> removed = <String>[];
  final List<String> installAttempts = <String>[];

  void seed(ChatModule module) => modules[module.name] = module;

  @override
  Future<List<ChatModule>> listInstalled() async =>
      modules.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<ChatModule?> get(String name) async =>
      modules[ModuleManifest.sanitizeName(name)];

  @override
  ChatModule? getSync(String name) =>
      modules[ModuleManifest.sanitizeName(name)];

  @override
  Future<void> ensureCacheLoaded() async {}

  @override
  Future<bool> remove(String name) async {
    removed.add(name);
    return modules.remove(ModuleManifest.sanitizeName(name)) != null;
  }

  @override
  Future<ModuleInstallResult> installFromZip(String zipPath) async {
    installAttempts.add(zipPath);
    return ModuleInstallResult(ok: false, message: 'not scripted');
  }
}

ChatModule _module(
  String name, {
  List<ModulePermission> permissions = const <ModulePermission>[
    ModulePermission.storage,
  ],
}) {
  return ChatModule(
    manifest: ModuleManifest(
      name: name,
      version: '2.5.0',
      title: name,
      description: '$name description',
      entry: 'main.js',
      permissions: permissions.toSet(),
    ),
    path: '/tmp/modules/$name',
    installedAt: DateTime(2026, 1, 1),
  );
}

Widget _host(List<Override> overrides, Directory tempDir) => ProviderScope(
  overrides: <Override>[
    // Full app override set (settings repo, lock, JS runtime, ...) —
    // the SDK docs viewer reads the language preference.
    ...testOverrides(dir: tempDir, writeScreenshots: false),
    ...overrides,
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      zLocalizationsDelegate,
    ],
    supportedLocales: const <Locale>[Locale('en'), Locale('id')],
    home: const ModulesScreenHost(),
  ),
);

/// Pushes [ModulesScreen] so its AppBar/actions render inside a navigator.
class ModulesScreenHost extends StatelessWidget {
  const ModulesScreenHost({super.key});

  @override
  Widget build(BuildContext context) => const ModulesScreen();
}

void main() {
  late ScriptedModuleRegistry registry;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('modules_screen_test');
    registry = ScriptedModuleRegistry();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('modules screen lists installed modules with versions and '
      'permissions', (WidgetTester tester) async {
    registry.seed(_module('alpha'));
    registry.seed(_module('beta', permissions: <ModulePermission>[]));
    await tester.pumpWidget(
      _host(<Override>[
        moduleRegistryProvider.overrideWithValue(registry),
      ], tempDir),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('module-tile-alpha')), findsOneWidget);
    expect(find.text('v2.5.0'), findsNWidgets(2));
    expect(find.text('alpha description'), findsOneWidget);
    expect(find.text('storage'), findsOneWidget);
  });

  testWidgets('empty state shows the install hint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<Override>[
        moduleRegistryProvider.overrideWithValue(registry),
      ], tempDir),
    );
    await tester.pumpAndSettle();

    expect(find.text('No modules installed yet.'), findsOneWidget);
    expect(find.byKey(const Key('modules-install')), findsOneWidget);
  });

  testWidgets('remove flow: confirm dialog deletes the module', (
    WidgetTester tester,
  ) async {
    registry.seed(_module('alpha'));
    await tester.pumpWidget(
      _host(<Override>[
        moduleRegistryProvider.overrideWithValue(registry),
      ], tempDir),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('module-remove-alpha')));
    await tester.pumpAndSettle();
    expect(find.text('Remove module?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(registry.removed, <String>['alpha']);
    expect(find.byKey(const Key('module-tile-alpha')), findsNothing);
  });

  testWidgets('SDK documentation opens and renders the shipped asset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(<Override>[
        moduleRegistryProvider.overrideWithValue(registry),
      ], tempDir),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('modules-sdk-docs')));
    await tester.pumpAndSettle();

    expect(find.text('SDK documentation'), findsOneWidget);
    expect(find.textContaining('ZAgents Module SDK'), findsWidgets);
  });

  testWidgets('permission consent dialog lists requested capabilities and '
      'returns the decision', (WidgetTester tester) async {
    final ChatModule mod = _module('alpha');
    bool? allowed;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            zLocalizationsDelegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('id')],
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () async {
                allowed = await ModulesScreen.confirmPermissions(
                  context,
                  ref,
                  mod,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Allow \u201calpha\u201d to:'), findsOneWidget);
    expect(find.text('storage'), findsOneWidget);

    await tester.tap(find.byKey(const Key('module-permission-allow')));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
  });

  testWidgets('consent is skipped for modules without permissions', (
    WidgetTester tester,
  ) async {
    final ChatModule mod = _module('bare', permissions: <ModulePermission>[]);
    bool? allowed;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            zLocalizationsDelegate,
          ],
          supportedLocales: const <Locale>[Locale('en'), Locale('id')],
          home: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () async {
                allowed = await ModulesScreen.confirmPermissions(
                  context,
                  ref,
                  mod,
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
  });
}
