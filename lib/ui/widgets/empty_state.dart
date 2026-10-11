import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../theme.dart';

/// Empty state with brand + suggestion chips (Z.AI style).
class EmptyState extends ConsumerWidget {
  const EmptyState({super.key});

  static const List<String> _suggestions = <String>[
    'Buka wikipedia.org lalu rangkum halaman utamanya',
    'Cari harga Bitcoin hari ini dan ambil screenshot',
    'Buat file catatan.txt berisi rencana harian',
    'Jelaskan cara kerja tool calling pada LLM',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'Agent AI di perangkat Anda — browsing, screenshot,\ndan kelola file langsung dari chat.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMutedTextColor, height: 1.5),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final String suggestion in _suggestions)
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
