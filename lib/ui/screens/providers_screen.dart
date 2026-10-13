import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';
import 'preset_editor_screen.dart';

/// Full-screen provider management: every preset is a card with its key
/// status, model and cache size. Tap a card to edit it in the full-screen
/// [PresetEditorScreen]; the bolt action switches the active connection.
class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  void _activate(BuildContext context, WidgetRef ref, ProviderPreset preset) {
    final AppStrings strings = stringsOf(context);
    final AppSettings settings = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(
            providerName: preset.name,
            baseUrl: preset.baseUrl,
            apiKey: preset.apiKey,
            model: preset.model,
          ),
        );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(strings.providerActivatedSnack(preset.name))),
      );
  }

  void _openEditor(BuildContext context, ProviderPreset preset) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PresetEditorScreen(preset: preset),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings strings = stringsOf(context);
    final ZPalette palette = context.palette;
    final AppSettings settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.providersTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('add-provider-button'),
            tooltip: strings.addProvider,
            icon: const Icon(Icons.add_rounded),
            onPressed: () =>
                _openEditor(context, ProviderPreset(id: newId(), name: '')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _hintCard(context, strings, palette),
            const SizedBox(height: 12),
            for (final ProviderPreset preset in settings.presets)
              _ProviderCard(
                key: Key('provider-${preset.name}'),
                preset: preset,
                isActive: preset.name == settings.providerName,
                strings: strings,
                palette: palette,
                onOpen: () => _openEditor(context, preset),
                onUse: () => _activate(context, ref, preset),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('add-provider-bottom'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.addProvider),
              onPressed: () =>
                  _openEditor(context, ProviderPreset(id: newId(), name: '')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _hintCard(
    BuildContext context,
    AppStrings strings,
    ZPalette palette,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.zSurfaceAlt,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.zBorder),
    ),
    child: Row(
      children: <Widget>[
        Icon(Icons.info_outline_rounded, size: 18, color: palette.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            strings.providersHint,
            style: TextStyle(fontSize: 12, color: palette.muted, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.preset,
    required this.isActive,
    required this.strings,
    required this.palette,
    required this.onOpen,
    required this.onUse,
  });

  final ProviderPreset preset;
  final bool isActive;
  final AppStrings strings;
  final ZPalette palette;
  final VoidCallback onOpen;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final String host = presetHostLabel(preset.baseUrl);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.zSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? kAccentColor : context.zBorder,
                width: isActive ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                _avatar(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isActive) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kAccentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                strings.activeBadge,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: kAccentColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              <String>[
                                if (host.isNotEmpty) host,
                                preset.model.isNotEmpty ? preset.model : '—',
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Icon(
                            preset.hasKey
                                ? Icons.key_rounded
                                : Icons.key_off_rounded,
                            size: 13,
                            color: preset.hasKey
                                ? Colors.green.shade400
                                : palette.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            preset.hasKey
                                ? strings.presetHasKey
                                : strings.presetNoKey,
                            style: TextStyle(
                              fontSize: 11,
                              color: preset.hasKey
                                  ? Colors.green.shade400
                                  : palette.muted,
                            ),
                          ),
                          if (preset.hasModelsCache) ...<Widget>[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.list_alt_rounded,
                              size: 13,
                              color: palette.muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                strings.modelsCachedCount(
                                  preset.modelsCache.length,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.muted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: Key('use-provider-${preset.name}'),
                  tooltip: strings.useProviderTooltip,
                  icon: Icon(
                    isActive
                        ? Icons.check_circle_rounded
                        : Icons.electric_bolt_rounded,
                    size: 22,
                    color: isActive ? kAccentColor : palette.muted,
                  ),
                  onPressed: onUse,
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final String letter = preset.name.isNotEmpty
        ? preset.name.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: isActive ? kBrandGradient : null,
        color: isActive ? null : context.zSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.transparent : context.zBorder,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: isActive ? Colors.white : palette.muted,
        ),
      ),
    );
  }
}
