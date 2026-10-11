import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../theme.dart';
import '../widgets/model_picker.dart';

/// Provider, agent and language configuration screen. Every change is
/// persisted immediately via [SettingsController].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = ref.read(settingsProvider);
    _baseUrl = TextEditingController(text: settings.baseUrl);
    _apiKey = TextEditingController(text: settings.apiKey);
    _model = TextEditingController(text: settings.model);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    super.dispose();
  }

  void _commit({
    String? providerName,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? agentMode,
    bool? automationEnabled,
    int? maxSteps,
    String? languageCode,
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
            maxSteps: maxSteps,
            languageCode: languageCode,
          ),
        );
  }

  /// Opens the shared model picker sheet; after it closes the model field
  /// is synced with whatever the user picked there.
  Future<void> _openModelPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurfaceColor,
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

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    final AppSettings settings = ref.watch(settingsProvider);
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
            _sectionTitle(strings.providerSection),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    key: const Key('provider-dropdown'),
                    initialValue: settings.providerName,
                    decoration: InputDecoration(
                      labelText: strings.providerPreset,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final String name in providerPresets.keys)
                        DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                    ],
                    onChanged: (String? name) {
                      if (name == null) return;
                      final String? presetUrl = providerPresets[name];
                      if (presetUrl != null && presetUrl.isNotEmpty) {
                        _baseUrl.text = presetUrl;
                      }
                      // Switching providers: adopt the new provider's default
                      // model when the current one is empty or is another
                      // provider's default (avoids stale cross-provider ids).
                      final String currentModel = _model.text.trim();
                      final bool foreignDefault =
                          providerDefaultModels.values.contains(currentModel) &&
                          providerDefaultModels[name] != currentModel;
                      if (currentModel.isEmpty || foreignDefault) {
                        _model.text = providerDefaultModels[name] ?? '';
                      }
                      _commit(
                        providerName: name,
                        baseUrl: _baseUrl.text.trim(),
                        model: _model.text.trim(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('base-url-field'),
                    controller: _baseUrl,
                    decoration: InputDecoration(
                      labelText: strings.baseUrlLabel,
                      hintText: 'https://openrouter.ai/api/v1',
                    ),
                    onSubmitted: (_) => _commit(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('api-key-field'),
                    controller: _apiKey,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: strings.apiKeyLabel,
                      helperText: strings.apiKeyStoredLocally,
                      helperMaxLines: 2,
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
                    onSubmitted: (_) => _commit(),
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
                    onSubmitted: (_) => _commit(),
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
                          backgroundColor: kSurfaceColor,
                          side: const BorderSide(color: kBorderColor),
                          onPressed: () {
                            _model.text = model;
                            _commit(model: model);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: kMutedTextColor,
                      ),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: kMutedTextColor,
                      ),
                    ),
                    value: settings.automationEnabled,
                    onChanged: (bool value) =>
                        _commit(automationEnabled: value),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.maxStepsTitle),
                    subtitle: Slider(
                      key: const Key('max-steps-slider'),
                      min: 1,
                      max: 12,
                      divisions: 11,
                      label: '${settings.maxSteps}',
                      value: settings.maxSteps.toDouble(),
                      onChanged: (double value) =>
                          setState(() => _commit(maxSteps: value.round())),
                    ),
                    trailing: Text('${settings.maxSteps}'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle(strings.languageSection),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    strings.languageSubtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kMutedTextColor,
                    ),
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
                style: const TextStyle(
                  fontSize: 12.5,
                  color: kMutedTextColor,
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
      color: kSurfaceColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kBorderColor),
    ),
    // Material so ListTiles can paint their ink on a proper ancestor.
    child: Material(
      type: MaterialType.transparency,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}
