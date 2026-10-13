import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/model_picker.dart';
import 'context_screen.dart';
import 'files_screen.dart';
import 'node_screen.dart';

/// App configuration: appearance (theme), provider presets (each with its
/// own API key), agent behaviour (max steps 1-100 via slider + custom
/// input), context manager, Node.js runtime, session import/export and
/// language. Every change is persisted immediately via [SettingsController].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _maxSteps;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = ref.read(settingsProvider);
    _baseUrl = TextEditingController(text: settings.baseUrl);
    _apiKey = TextEditingController(text: settings.apiKey);
    _model = TextEditingController(text: settings.model);
    _maxSteps = TextEditingController(text: '${settings.maxSteps}');
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _maxSteps.dispose();
    super.dispose();
  }

  void _commit({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? agentMode,
    bool? automationEnabled,
    bool? runInBackground,
    Object? maxSteps,
    String? languageCode,
    ThemeModeSetting? themeMode,
    List<ProviderPreset>? presets,
  }) {
    final AppSettings current = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .update(
          current.copyWith(
            providerName: providerName,
            baseUrl: baseUrl ?? _baseUrl.text.trim(),
            apiKey: apiKey ?? _apiKey.text,
            model: model ?? _model.text.trim(),
            agentMode: agentMode,
            automationEnabled: automationEnabled,
            runInBackground: runInBackground,
            maxSteps: maxSteps ?? current.maxSteps,
            languageCode: languageCode,
            themeMode: themeMode,
            presets: presets,
          ),
        );
    if (mounted) {
      setState(() {
        if (_maxSteps.text != '${current.maxSteps}') {
          _maxSteps.text = '${current.maxSteps}';
        }
      });
    }
  }

  /// Opens the shared model picker sheet; after it closes the model field
  /// is synced with whatever the user picked there.
  Future<void> _openModelPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.zSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => const ModelPickerSheet(),
    );
    if (!mounted) return;
    setState(() {
      _model.text = ref.read(settingsProvider).model;
    });
  }

  /// Activates a preset: copies its stored base URL / key / model into the
  /// active connection fields.
  void _applyPreset(ProviderPreset preset) {
    setState(() {
      _baseUrl.text = preset.baseUrl;
      _apiKey.text = preset.apiKey;
      _model.text = preset.model;
    });
    _commit(
      providerName: preset.name,
      baseUrl: preset.baseUrl,
      apiKey: preset.apiKey,
      model: preset.model,
    );
  }

  /// Writes the current active fields back into the preset of the same
  /// name (so editing the key here also updates the preset's own key).
  void _syncActivePreset() {
    final AppSettings settings = ref.read(settingsProvider);
    final List<ProviderPreset> presets = settings.presets
        .map(
          (ProviderPreset p) => p.name == settings.providerName
              ? p.copyWith(
                  baseUrl: _baseUrl.text.trim(),
                  apiKey: _apiKey.text,
                  model: _model.text.trim(),
                )
              : p,
        )
        .toList();
    if (!presets.any((ProviderPreset p) => p.name == settings.providerName)) {
      presets.insert(
        0,
        ProviderPreset(
          id: newId(),
          name: settings.providerName,
          baseUrl: _baseUrl.text.trim(),
          apiKey: _apiKey.text,
          model: _model.text.trim(),
        ),
      );
    }
    _commit(presets: presets);
  }

  /// Add or edit a preset in a dialog; returns the saved preset.
  Future<void> _editPreset([ProviderPreset? existing]) async {
    final AppStrings strings = stringsOf(context);
    final TextEditingController name = TextEditingController(
      text: existing?.name ?? '',
    );
    final TextEditingController baseUrl = TextEditingController(
      text: existing?.baseUrl ?? '',
    );
    final TextEditingController apiKey = TextEditingController(
      text: existing?.apiKey ?? '',
    );
    final TextEditingController model = TextEditingController(
      text: existing?.model ?? '',
    );
    final (ProviderPreset?, bool)?
    result = await showDialog<(ProviderPreset?, bool)>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: context.zSurface,
        title: Text(
          existing == null ? strings.savePresetTitle : strings.editPreset,
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('preset-name-field'),
                autofocus: true,
                controller: name,
                decoration: InputDecoration(labelText: strings.presetNameLabel),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: baseUrl,
                decoration: InputDecoration(labelText: strings.baseUrlLabel),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apiKey,
                obscureText: true,
                decoration: InputDecoration(labelText: strings.apiKeyLabel),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: model,
                decoration: InputDecoration(labelText: strings.modelLabel),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop((null, true)),
              child: Text(
                strings.delete,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop((null, false)),
            child: Text(strings.cancel),
          ),
          TextButton(
            key: const Key('preset-save-button'),
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop((
                ProviderPreset(
                  id: existing?.id ?? newId(),
                  name: name.text.trim(),
                  baseUrl: baseUrl.text.trim(),
                  apiKey: apiKey.text,
                  model: model.text.trim(),
                ),
                false,
              ));
            },
            child: Text(strings.save),
          ),
        ],
      ),
    );
    if (result == null) return;
    final AppSettings settings = ref.read(settingsProvider);
    if (result.$2) {
      // Delete requested.
      final List<ProviderPreset> remaining = settings.presets
          .where((ProviderPreset p) => p.id != existing!.id)
          .toList();
      _commit(presets: remaining);
      return;
    }
    final ProviderPreset saved = result.$1!;
    final bool replacing = settings.presets.any(
      (ProviderPreset p) => p.id == saved.id,
    );
    final List<ProviderPreset> presets = replacing
        ? <ProviderPreset>[
            for (final ProviderPreset p in settings.presets)
              if (p.id == saved.id) saved else p,
          ]
        : <ProviderPreset>[...settings.presets, saved];
    _commit(presets: presets);
  }

  Future<void> _saveCurrentAsPreset() async {
    final AppSettings settings = ref.read(settingsProvider);
    await _editPreset(
      ProviderPreset(
        id: newId(),
        name: settings.providerName == 'Custom'
            ? 'My provider'
            : settings.providerName,
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text,
        model: _model.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final AppSettings settings = ref.watch(settingsProvider);
    final ZPalette palette = context.palette;
    final int contextActive =
        (ref.watch(contextListProvider).value ??
                ref.read(contextRepositoryProvider).load())
            .where((ContextEntry e) => e.enabled)
            .length;
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: SafeArea(
        // top:false: the AppBar already reserves the status bar height;
        // bottom keeps the last cards above the system navigation bar
        // (edge-to-edge is enforced on Android 15+).
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // -- Appearance ------------------------------------------------
            _sectionTitle(strings.appearanceSection),
            _card(
              child: SegmentedButton<ThemeModeSetting>(
                key: const Key('theme-mode-segmented'),
                segments: <ButtonSegment<ThemeModeSetting>>[
                  ButtonSegment<ThemeModeSetting>(
                    value: ThemeModeSetting.light,
                    icon: const Icon(Icons.light_mode_outlined, size: 18),
                    label: Text(strings.themeLight),
                  ),
                  ButtonSegment<ThemeModeSetting>(
                    value: ThemeModeSetting.dark,
                    icon: const Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text(strings.themeDark),
                  ),
                  ButtonSegment<ThemeModeSetting>(
                    value: ThemeModeSetting.system,
                    icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                    label: Text(strings.themeSystem),
                  ),
                ],
                selected: <ThemeModeSetting>{settings.themeMode},
                onSelectionChanged: (Set<ThemeModeSetting> selection) =>
                    _commit(themeMode: selection.first),
              ),
            ),
            const SizedBox(height: 16),

            // -- Provider presets ------------------------------------------
            _sectionTitle(strings.providerSection),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.presetsTitle,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                  const SizedBox(height: 8),
                  for (final ProviderPreset preset in settings.presets)
                    _PresetTile(
                      preset: preset,
                      isActive: preset.name == settings.providerName,
                      onApply: () => _applyPreset(preset),
                      onEdit: () => _editPreset(preset),
                    ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    key: const Key('save-preset-button'),
                    onPressed: _saveCurrentAsPreset,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: Text(strings.savePreset),
                  ),
                  const Divider(height: 24),
                  TextField(
                    key: const Key('base-url-field'),
                    controller: _baseUrl,
                    decoration: InputDecoration(
                      labelText: strings.baseUrlLabel,
                      hintText: 'https://openrouter.ai/api/v1',
                    ),
                    onSubmitted: (_) {
                      _commit();
                      _syncActivePreset();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('api-key-field'),
                    controller: _apiKey,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: strings.apiKeyLabel,
                      helperText: strings.apiKeyStoredLocally,
                      helperMaxLines: 3,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    onSubmitted: (_) {
                      _commit();
                      _syncActivePreset();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('model-field'),
                    controller: _model,
                    decoration: InputDecoration(
                      labelText: strings.modelLabel,
                      hintText: strings.modelHint,
                      helperText: strings.browseModelsHint,
                      suffixIcon: IconButton(
                        key: const Key('browse-models-button'),
                        tooltip: strings.browseModels,
                        icon: const Icon(Icons.manage_search_rounded),
                        onPressed: _openModelPicker,
                      ),
                    ),
                    onSubmitted: (_) {
                      _commit();
                      _syncActivePreset();
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String model in suggestedModels)
                        InputChip(
                          label: Text(
                            model,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: context.zSurface,
                          side: BorderSide(color: context.zBorder),
                          onPressed: () {
                            _model.text = model;
                            _commit(model: model);
                            _syncActivePreset();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Agent -----------------------------------------------------
            _sectionTitle(strings.agentSection),
            _card(
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    key: const Key('agent-mode-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.agentModeTitle),
                    subtitle: Text(
                      strings.agentModeSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.agentMode,
                    onChanged: (bool value) => _commit(agentMode: value),
                  ),
                  SwitchListTile(
                    key: const Key('automation-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.automationTitle),
                    subtitle: Text(
                      strings.automationSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.automationEnabled,
                    onChanged: (bool value) =>
                        _commit(automationEnabled: value),
                  ),
                  SwitchListTile(
                    key: const Key('background-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.runInBackgroundTitle),
                    subtitle: Text(
                      strings.runInBackgroundSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.runInBackground,
                    onChanged: (bool value) => _commit(runInBackground: value),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.maxStepsTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Slider(
                          key: const Key('max-steps-slider'),
                          min: minMaxSteps.toDouble(),
                          max: maxMaxSteps.toDouble(),
                          divisions: maxMaxSteps - minMaxSteps,
                          label: '${settings.maxSteps}',
                          value: settings.maxSteps.toDouble(),
                          onChanged: (double value) {
                            _maxSteps.text = '${value.round()}';
                            _commit(maxSteps: value.round());
                          },
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: TextField(
                          key: const Key('max-steps-field'),
                          controller: _maxSteps,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (String value) {
                            final int? parsed = int.tryParse(value);
                            final int clamped = clampMaxSteps(
                              parsed ?? settings.maxSteps,
                            );
                            _maxSteps.text = '$clamped';
                            _commit(maxSteps: clamped);
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      strings.maxStepsHint,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Context ---------------------------------------------------
            _sectionTitle(strings.contextSection),
            _card(
              child: ListTile(
                key: const Key('context-manager-tile'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.format_quote_rounded),
                title: Text(strings.contextManagerTitle),
                subtitle: Text(
                  strings.contextActiveCount(contextActive),
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ContextScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- Node.js ---------------------------------------------------
            _sectionTitle(strings.nodeSection),
            _card(
              child: ListTile(
                key: const Key('node-manager-tile'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.javascript_rounded),
                title: Text(strings.nodeManagerTitle),
                subtitle: Text(
                  strings.nodeManagerHint,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const NodeScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // -- Data ------------------------------------------------------
            _sectionTitle(strings.dataSection),
            _card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    key: const Key('files-tile'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_open_rounded),
                    title: Text(strings.filesTitle),
                    subtitle: Text(
                      strings.filesHint,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FilesScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Language --------------------------------------------------
            _sectionTitle(strings.languageSection),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.languageSubtitle,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                  RadioGroup<String>(
                    groupValue: settings.languageCode,
                    onChanged: (String? code) =>
                        _commit(languageCode: code ?? 'en'),
                    child: Column(
                      children: <Widget>[
                        RadioListTile<String>(
                          key: const Key('lang-en'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(strings.englishOption),
                          value: 'en',
                        ),
                        RadioListTile<String>(
                          key: const Key('lang-id'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(strings.indonesianOption),
                          value: 'id',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(strings.aboutSection),
            _card(
              child: Text(
                strings.aboutBody,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.muted,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: kMutedTextColor,
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: context.zSurface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.zBorder),
    ),
    // Material so ListTiles can paint their ink on a proper ancestor.
    child: Material(
      type: MaterialType.transparency,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

/// One provider preset row: tap to activate (applies its key), menu to edit
/// or delete. Shows key status so per-preset keys are visible at a glance.
class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.isActive,
    required this.onApply,
    required this.onEdit,
  });

  final ProviderPreset preset;
  final bool isActive;
  final VoidCallback onApply;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final ZPalette palette = context.palette;
    return ListTile(
      key: Key('preset-${preset.name}'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        isActive
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        size: 20,
        color: isActive ? kAccentColor : palette.muted,
      ),
      title: Text(
        preset.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              preset.baseUrl.isEmpty ? '—' : preset.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            preset.hasKey
                ? '· ${strings.presetHasKey}'
                : '· ${strings.presetNoKey}',
            style: TextStyle(
              fontSize: 11,
              color: preset.hasKey ? Colors.green.shade400 : palette.muted,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.more_vert_rounded, size: 18, color: palette.muted),
        onPressed: onEdit,
      ),
      onTap: onApply,
    );
  }
}
