import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';

/// Top-bar chip showing the active model; opens the picker sheet.
class ModelChip extends ConsumerWidget {
  const ModelChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final String model = ref.watch(settingsProvider.select((s) => s.model));
    return InkWell(
      key: const Key('model-chip'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: kSurfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: true,
        builder: (_) => const ModelPickerSheet(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kSurfaceAltColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kBorderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                model.isEmpty ? strings.pickModel : model,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: kMutedTextColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing suggested models + custom model input.
class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key});

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: ref.read(settingsProvider).model,
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _select(String model) {
    final AppSettings current = ref.read(settingsProvider);
    ref.read(settingsProvider.notifier).update(current.copyWith(model: model));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final AppSettings settings = ref.watch(settingsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                strings.pickModel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...suggestedModels.map(
              (String model) => ListTile(
                dense: true,
                leading: Icon(
                  model == settings.model
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 18,
                  color: model == settings.model
                      ? kAccentColor
                      : kMutedTextColor,
                ),
                title: Text(
                  model,
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                ),
                onTap: () => _select(model),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _customController,
                decoration: InputDecoration(
                  hintText: strings.customModelHint,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_rounded),
                    onPressed: () => _select(_customController.text.trim()),
                  ),
                ),
                onSubmitted: (String value) => _select(value.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
