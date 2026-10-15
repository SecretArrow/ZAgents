import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../../models/user_agent.dart';
import '../theme.dart';
import 'context_screen.dart';
import 'files_screen.dart';
import 'node_screen.dart';
import 'providers_screen.dart';

/// App configuration: appearance (theme), providers (full-screen manager),
/// agent behaviour (max steps 1-100 via slider + custom input), context
/// manager, Node.js runtime, files, import/export and language. Every
/// change is persisted immediately via [SettingsController].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _maxSteps;

  @override
  void initState() {
    super.initState();
    final AppSettings settings = ref.read(settingsProvider);
    _maxSteps = TextEditingController(text: '${settings.maxSteps}');
  }

  @override
  void dispose() {
    _maxSteps.dispose();
    super.dispose();
  }

  void _commit({
    bool? agentMode,
    bool? automationEnabled,
    bool? runUntilDone,
    bool? planFirst,
    bool? runInBackground,
    bool? askRandomUa,
    bool? autoTitle,
    Object? maxSteps,
    String? languageCode,
    ThemeModeSetting? themeMode,
    UaMode? uaMode,
  }) {
    final AppSettings current = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .update(
          current.copyWith(
            agentMode: agentMode,
            automationEnabled: automationEnabled,
            runUntilDone: runUntilDone,
            planFirst: planFirst,
            runInBackground: runInBackground,
            askRandomUa: askRandomUa,
            autoTitle: autoTitle,
            maxSteps: maxSteps ?? current.maxSteps,
            languageCode: languageCode,
            themeMode: themeMode,
            uaMode: uaMode,
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

            // -- Provider --------------------------------------------------
            _sectionTitle(strings.providerSection),
            _card(
              child: _ProviderSummaryTile(
                settings: settings,
                strings: strings,
                palette: palette,
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
                  SwitchListTile(
                    key: const Key('run-until-done-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.runUntilDoneTitle),
                    subtitle: Text(
                      strings.runUntilDoneSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.runUntilDone,
                    onChanged: (bool value) => _commit(runUntilDone: value),
                  ),
                  SwitchListTile(
                    key: const Key('plan-first-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.planFirstTitle),
                    subtitle: Text(
                      strings.planFirstSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.planFirst,
                    onChanged: (bool value) => _commit(planFirst: value),
                  ),
                  SwitchListTile(
                    key: const Key('auto-title-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(strings.autoTitleTitle),
                    subtitle: Text(
                      strings.autoTitleSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.autoTitle,
                    onChanged: (bool value) => _commit(autoTitle: value),
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
                          // The cap is bypassed while "Run until done" is
                          // active — dim + disable the control.
                          onChanged: settings.runUntilDone
                              ? null
                              : (double value) {
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
                          enabled: !settings.runUntilDone,
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
                      settings.runUntilDone
                          ? strings.runUntilDoneHint
                          : strings.maxStepsHint,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- User Agent --------------------------------------------------
            _sectionTitle(strings.uaSection),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<UaMode>(
                    key: const Key('ua-mode-dropdown'),
                    initialValue: settings.uaMode,
                    decoration: InputDecoration(
                      labelText: strings.uaModeTitle,
                      helperMaxLines: 3,
                    ),
                    items: <DropdownMenuItem<UaMode>>[
                      DropdownMenuItem<UaMode>(
                        value: UaMode.auto,
                        child: Text(strings.uaModeAuto),
                      ),
                      DropdownMenuItem<UaMode>(
                        value: UaMode.desktop,
                        child: Text(strings.uaModeDesktop),
                      ),
                      DropdownMenuItem<UaMode>(
                        value: UaMode.android,
                        child: Text(strings.uaModeAndroid),
                      ),
                    ],
                    onChanged: (UaMode? mode) {
                      if (mode != null) _commit(uaMode: mode);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.uaModeHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.muted,
                      height: 1.4,
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.devices_rounded,
                        size: 20,
                        color: palette.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              strings.uaCurrentLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ref
                                  .read(userAgentManagerProvider)
                                  .resolve(settings.uaMode)
                                  .label,
                              key: const Key('ua-current-preview'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('ua-rotate-button'),
                        tooltip: strings.uaRotateTooltip,
                        icon: const Icon(Icons.autorenew_rounded),
                        onPressed: () async {
                          await ref
                              .read(userAgentManagerProvider)
                              .rotate(settings.uaMode);
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  SwitchListTile(
                    key: const Key('ask-random-ua-switch'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(strings.uaAskRandomTitle),
                    subtitle: Text(
                      strings.uaAskRandomSubtitle,
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    value: settings.askRandomUa,
                    onChanged: (bool value) => _commit(askRandomUa: value),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    key: const Key('about-creator'),
                    children: <Widget>[
                      Icon(Icons.code_rounded, size: 20, color: palette.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          strings.createdBy('Maragung'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.aboutBody,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: palette.muted,
                      height: 1.5,
                    ),
                  ),
                ],
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

/// Compact summary of the active provider connection. Opens the full-screen
/// [ProvidersScreen] where CRUD happens (the old inline fields + modal
/// dialog were cramped, overflowed under the keyboard and lost edits).
class _ProviderSummaryTile extends StatelessWidget {
  const _ProviderSummaryTile({
    required this.settings,
    required this.strings,
    required this.palette,
  });

  final AppSettings settings;
  final AppStrings strings;
  final ZPalette palette;

  @override
  Widget build(BuildContext context) {
    final ProviderPreset? active = settings.activePreset;
    final bool hasKey = active?.hasKey ?? settings.apiKey.trim().isNotEmpty;
    final String host = presetHostLabel(settings.baseUrl);
    return ListTile(
      key: const Key('providers-tile'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.dns_rounded,
        size: 24,
        color: hasKey ? kAccentColor : palette.muted,
      ),
      title: Text(
        settings.providerName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      subtitle: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              <String>[
                if (host.isNotEmpty) host,
                settings.model.isNotEmpty ? settings.model : '—',
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: palette.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            hasKey ? '· ${strings.presetHasKey}' : '· ${strings.presetNoKey}',
            style: TextStyle(
              fontSize: 11,
              color: hasKey ? Colors.green.shade400 : palette.muted,
            ),
          ),
        ],
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ProvidersScreen())),
    );
  }
}
