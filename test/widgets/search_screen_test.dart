import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/di.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/models/models.dart';
import 'package:zagents/services/chat_store.dart';
import 'package:zagents/ui/screens/search_screen.dart';
import 'package:zagents/ui/theme.dart';

import '../../test/fakes/fakes.dart';

/// In-memory ChatStore fake: searchAll returns canned hits, load() feeds
/// openChat — no disk IO (which never completes in the fake-async zone).
class FakeChatStore implements ChatStore {
  final List<ChatSearchHit> hits;
  final Map<String, List<ChatMessage>> sessions;

  FakeChatStore({
    required this.hits,
    this.sessions = const <String, List<ChatMessage>>{},
  });

  @override
  Future<Directory> Function() get resolveBaseDir => throw UnimplementedError();

  @override
  Future<List<ChatSummary>> listSummaries() async => <ChatSummary>[];

  @override
  Future<List<ChatSearchHit>> searchAll(String query, {int limit = 50}) async =>
      query.trim().isEmpty ? <ChatSearchHit>[] : hits;

  @override
  Future<void> save({
    required String id,
    required String title,
    required List<ChatMessage> messages,
  }) async {}

  @override
  Future<List<ChatMessage>?> load(String id) async => sessions[id];

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> rename(String id, String title) async {}
}

Widget wrap(
  Widget child, {
  required Directory dir,
  List<Override> extra = const <Override>[],
}) => ProviderScope(
  overrides: <Override>[
    ...testOverrides(
      dir: dir,
      settings: AppSettings(apiKey: 'k', autoTitle: false),
      writeScreenshots: false,
    ),
    ...extra,
  ],
  child: MaterialApp(
    theme: buildDarkTheme(),
    locale: const Locale('en'),
    supportedLocales: const <Locale>[Locale('en'), Locale('id')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      zLocalizationsDelegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('home-marker'),
              TextButton(
                key: const Key('open-search'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
                child: const Text('open'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zagents_search_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('typing a query renders ranked results after the debounce', (
    WidgetTester tester,
  ) async {
    final FakeChatStore fake = FakeChatStore(
      hits: <ChatSearchHit>[
        ChatSearchHit(
          sessionId: 's1',
          title: 'Resep kue cokelat',
          snippet: 'Cara membuat kue cokelat yang lembut…',
          createdAt: DateTime(2025, 3, 2),
        ),
        ChatSearchHit(
          sessionId: 's2',
          title: 'Jadwal kereta api',
          snippet: 'Kapan jadwal kereta terbaru keluar?',
          role: Role.user,
          createdAt: DateTime(2025, 3, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      wrap(
        const SizedBox.shrink(),
        dir: tempDir,
        extra: <Override>[chatStoreProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pump();

    // Untouched screen shows the initial hint, not "no results".
    await tester.tap(find.byKey(const Key('open-search')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(
      find.text('Type to search your conversation titles and messages.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'kereta');
    // 300 ms debounce timer, then the (fake, instant) search itself.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(find.text('Resep kue cokelat'), findsOneWidget);
    expect(find.text('Jadwal kereta api'), findsOneWidget);
    // The matched substring is bolded inside the snippet's RichText.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is RichText &&
            (w.text is TextSpan) &&
            (w.text as TextSpan).toPlainText().contains('kereta'),
      ),
      findsWidgets,
    );
  });

  testWidgets('no matches show the localized empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox.shrink(),
        dir: tempDir,
        extra: <Override>[
          chatStoreProvider.overrideWithValue(
            FakeChatStore(hits: <ChatSearchHit>[]),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-search')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    await tester.enterText(find.byKey(const Key('search-field')), 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    expect(find.text('No conversations found.'), findsOneWidget);
  });

  testWidgets('tapping a hit opens the session and pops back', (
    WidgetTester tester,
  ) async {
    final FakeChatStore fake = FakeChatStore(
      hits: <ChatSearchHit>[
        ChatSearchHit(
          sessionId: 's2',
          title: 'Jadwal kereta api',
          snippet: 'Kapan jadwal kereta terbaru keluar?',
          role: Role.user,
          createdAt: DateTime(2025, 3, 1),
        ),
      ],
      sessions: <String, List<ChatMessage>>{
        's2': <ChatMessage>[ChatMessage.user('Kapan jadwal kereta terbaru?')],
      },
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...testOverrides(
            dir: tempDir,
            settings: AppSettings(apiKey: 'k', autoTitle: false),
            writeScreenshots: false,
          ),
          chatStoreProvider.overrideWithValue(fake),
        ],
        child: Builder(
          builder: (BuildContext context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: buildDarkTheme(),
              locale: const Locale('en'),
              supportedLocales: const <Locale>[Locale('en'), Locale('id')],
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                zLocalizationsDelegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Builder(
                  builder: (BuildContext context) => Center(
                    child: TextButton(
                      key: const Key('open-search'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SearchScreen(),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-search')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
    await tester.enterText(find.byKey(const Key('search-field')), 'kereta');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    await tester.tap(find.text('Jadwal kereta api'));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );

    expect(
      container.read(chatControllerProvider).sessionId,
      's2',
      reason: 'the hit must open its conversation',
    );
    expect(
      find.text('open'),
      findsOneWidget,
      reason: 'search screen must pop back to the home page after opening',
    );
  });
}
