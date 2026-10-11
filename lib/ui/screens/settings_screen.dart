import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../models/models.dart';
import '../theme.dart';

/// Provider & agent configuration screen. Every change is persisted
/// immediately via [SettingsController].
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
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _sectionTitle('Provider AI'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  key: const Key('provider-dropdown'),
                  initialValue: settings.providerName,
                  decoration: const InputDecoration(
                    labelText: 'Preset provider',
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final String name in providerPresets.keys)
                      DropdownMenuItem<String>(value: name, child: Text(name)),
                  ],
                  onChanged: (String? name) {
                    if (name == null) return;
                    final String? presetUrl = providerPresets[name];
                    _baseUrl.text = (presetUrl == null || presetUrl.isEmpty)
                        ? _baseUrl.text
                        : presetUrl;
                    _commit(providerName: name, baseUrl: _baseUrl.text.trim());
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('base-url-field'),
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL (OpenAI-compatible)',
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
                    labelText: 'API key',
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
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText:
                        'mis. z-ai/glm-4.6 atau anthropic/claude-sonnet-4.5',
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
          _sectionTitle('Agent'),
          _card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  key: const Key('agent-mode-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mode Agent'),
                  subtitle: const Text(
                    'Aktifkan tool calling: browsing, screenshot, file. '
                    'Matikan untuk chat biasa.',
                    style: TextStyle(fontSize: 12, color: kMutedTextColor),
                  ),
                  value: settings.agentMode,
                  onChanged: (bool value) => _commit(agentMode: value),
                ),
                SwitchListTile(
                  key: const Key('automation-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Otomasi browser'),
                  subtitle: const Text(
                    'Izinkan agent mengendalikan browser tersemat.',
                    style: TextStyle(fontSize: 12, color: kMutedTextColor),
                  ),
                  value: settings.automationEnabled,
                  onChanged: (bool value) => _commit(automationEnabled: value),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Maks. langkah agent'),
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
          _sectionTitle('Tentang'),
          _card(
            child: const Text(
              'ZAgents v1.0.0 — klon UI agent mode chat.z.ai untuk Android, '
              'dengan custom provider OpenAI-compatible (OpenRouter, Z.AI, '
              'OpenAI, DeepSeek, Groq, dan lainnya). API key disimpan hanya '
              'di penyimpanan lokal perangkat.',
              style: TextStyle(
                fontSize: 12.5,
                color: kMutedTextColor,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
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
