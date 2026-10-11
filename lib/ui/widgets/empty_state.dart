import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../theme.dart';

/// Empty state with brand + suggestion chips (Z.AI style).
class EmptyState extends ConsumerWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandMark(size: 64),
            const SizedBox(height: 16),
            const Text(
              'ZAgents',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              strings.emptySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMutedTextColor, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final String suggestion in strings.suggestions)
                  ActionChip(
                    label: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: kSurfaceAltColor,
                    side: const BorderSide(color: kBorderColor),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      ref
                          .read(chatControllerProvider.notifier)
                          .send(suggestion);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
