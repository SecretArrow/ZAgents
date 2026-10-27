import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zagents/l10n/app_strings.dart';
import 'package:zagents/ui/theme.dart';
import 'package:zagents/ui/widgets/skill_selector_sheet.dart';

/// v1.49.0 per-chat skill selector sheet: selection round-trip contract of
/// [SkillSelectorSheet.show] (Apply / Use global default / Clear /
/// barrier-dismiss), checkbox prefill, wallet badge and the search filter.
/// No registry, no I/O — the sheet takes a plain [SkillOption] list.
void main() {
  const List<SkillOption> options = <SkillOption>[
    SkillOption(name: 'a', title: 'Alpha', description: 'alpha skill'),
    SkillOption(
      name: 'b',
      title: 'Beta',
      description: 'beta skill',
      wallet: true,
    ),
    SkillOption(name: 'c', title: 'Gamma', description: 'gamma skill'),
  ];

  late Future<List<String>?>? pending;

  Future<void> openSheet(
    WidgetTester tester, {
    List<String>? currentSelection,
  }) async {
    pending = null;
    await tester.pumpWidget(
      MaterialApp(
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
                onPressed: () {
                  pending = SkillSelectorSheet.show(
                    context,
                    options: options,
                    currentSelection: currentSelection,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder item(String name) => find.byKey(Key('skill-sheet-item-$name'));

  testWidgets('prefills the checkboxes from currentSelection and badges the '
      'wallet option', (WidgetTester tester) async {
    await openSheet(tester, currentSelection: <String>['a']);

    final CheckboxListTile tileA = tester.widget<CheckboxListTile>(item('a'));
    final CheckboxListTile tileB = tester.widget<CheckboxListTile>(item('b'));
    final CheckboxListTile tileC = tester.widget<CheckboxListTile>(item('c'));
    expect(tileA.value, isTrue);
    expect(tileB.value, isFalse);
    expect(tileC.value, isFalse);
    // Only the wallet-declared option carries the badge.
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsOneWidget);
    const AppStrings strings = AppStringsEn();
    expect(find.text(strings.skillSheetTitle), findsOneWidget);
    expect(find.text(strings.skillSheetHint), findsOneWidget);
  });

  testWidgets('tapping another option and applying resolves with the merged '
      'selection', (WidgetTester tester) async {
    await openSheet(tester, currentSelection: <String>['a']);

    await tester.tap(item('c'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('skill-sheet-apply')));
    await tester.pumpAndSettle();

    final List<String>? result = await pending;
    expect(result, <String>['a', 'c']);
  });

  testWidgets('Clear resolves with the empty selection', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, currentSelection: <String>['a']);

    await tester.tap(find.byKey(const Key('skill-sheet-clear')));
    await tester.pumpAndSettle();

    expect(await pending, isEmpty);
  });

  testWidgets('Use global default resolves with null', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, currentSelection: <String>['a']);

    await tester.tap(find.byKey(const Key('skill-sheet-use-global')));
    await tester.pumpAndSettle();

    expect(await pending, isNull);
  });

  testWidgets('the search field filters the visible options', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const Key('skill-sheet-search-field')),
      'beta',
    );
    await tester.pump();

    expect(item('b'), findsOneWidget);
    expect(item('a'), findsNothing);
    expect(item('c'), findsNothing);
  });

  testWidgets('a query with no match renders the empty hint', (
    WidgetTester tester,
  ) async {
    await openSheet(tester);

    await tester.enterText(
      find.byKey(const Key('skill-sheet-search-field')),
      'zzz',
    );
    await tester.pump();

    expect(item('a'), findsNothing);
    expect(item('b'), findsNothing);
    expect(item('c'), findsNothing);
    expect(find.text(const AppStringsEn().skillsEmptyTitle), findsOneWidget);
  });

  testWidgets('barrier dismissal resolves with the caller\'s current '
      'selection (unchanged)', (WidgetTester tester) async {
    await openSheet(tester, currentSelection: <String>['a']);

    // Tap the scrim ABOVE the sheet — showModalBottomSheet pops null and
    // show() must translate that into "keep the current selection".
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    expect(await pending, <String>['a']);
  });
}
