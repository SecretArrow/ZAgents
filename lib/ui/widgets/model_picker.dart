import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di.dart';
import '../../l10n/app_strings.dart';
import '../../models/models.dart';
import '../../services/model_catalog.dart';
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
        backgroundColor: context.zSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: true,
        builder: (_) => const ModelPickerSheet(),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.zSurfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.zBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Shrinks with ellipsis when the app bar runs out of width.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  model.isEmpty ? strings.pickModel : model,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: context.zMuted,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ModelFilter { all, tools, free }

/// Bottom sheet with the live model catalog of the active provider:
/// search box, filter chips (all / tool-calling / free) and paging.
/// Falls back to [suggestedModels] when no API key is set or the fetch
/// fails, and always allows typing a custom model id.
class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key});

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  late final TextEditingController _customController;
  final TextEditingController _searchController = TextEditingController();

  Future<List<RemoteModel>>? _catalogFuture;
  String? _errorMessage;
  String _query = '';
  _ModelFilter _filter = _ModelFilter.all;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: ref.read(settingsProvider).model,
    );
    _reload();
  }

  @override
  void dispose() {
    _customController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasApiKey => ref.read(settingsProvider).apiKey.trim().isNotEmpty;

  /// Re-fetches the catalog. The future never fails: fetch errors are
  /// captured into [_errorMessage] and surfaced as an empty result, so the
  /// UI switches to the error card without async-error plumbing.
  void _reload() {
    setState(() {
      _page = 0;
      _errorMessage = null;
      if (_hasApiKey) {
        final AppSettings settings = ref.read(settingsProvider);
        _catalogFuture = ref
            .read(modelCatalogProvider)
            .fetchModels(baseUrl: settings.baseUrl, apiKey: settings.apiKey)
            .then<List<RemoteModel>>(
              (List<RemoteModel> models) => models,
              onError: (Object e) {
                if (mounted) {
                  setState(() => _errorMessage = e.toString());
                }
                return const <RemoteModel>[];
              },
            );
      } else {
        _catalogFuture = null;
      }
    });
  }

  void _select(String model) {
    final String trimmed = model.trim();
    if (trimmed.isEmpty) return;
    final AppSettings current = ref.read(settingsProvider);
    ref
        .read(settingsProvider.notifier)
        .update(current.copyWith(model: trimmed));
    Navigator.of(context).pop();
  }

  void _setFilter(_ModelFilter filter) {
    setState(() {
      _filter = filter;
      _page = 0;
    });
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _page = 0;
    });
  }

  List<RemoteModel> _applyFilters(List<RemoteModel> models) {
    final String q = _query.trim().toLowerCase();
    Iterable<RemoteModel> out = models;
    if (q.isNotEmpty) {
      out = out.where(
        (RemoteModel m) =>
            m.id.toLowerCase().contains(q) || m.name.toLowerCase().contains(q),
      );
    }
    switch (_filter) {
      case _ModelFilter.all:
        break;
      case _ModelFilter.tools:
        out = out.where((RemoteModel m) => m.supportsTools);
      case _ModelFilter.free:
        out = out.where((RemoteModel m) => m.isFree);
    }
    final List<RemoteModel> list = out.toList()
      ..sort((RemoteModel a, RemoteModel b) => a.id.compareTo(b.id));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = stringsOf(context);
    // The keyboard inset must come out of the sheet height, otherwise the
    // sheet grows taller than the screen and its header collides with the
    // status bar while the search field is focused.
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final double sheetHeight = math.max(
      320.0,
      MediaQuery.of(context).size.height * 0.85 - keyboardInset,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: sheetHeight,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _header(strings),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const Key('model-search-field'),
                  controller: _searchController,
                  onChanged: _setQuery,
                  decoration: InputDecoration(
                    hintText: strings.searchModelsHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _setQuery('');
                            },
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    _filterChip(
                      key: 'model-filter-all',
                      label: strings.filterAll,
                      filter: _ModelFilter.all,
                    ),
                    _filterChip(
                      key: 'model-filter-tools',
                      label: strings.filterTools,
                      filter: _ModelFilter.tools,
                    ),
                    _filterChip(
                      key: 'model-filter-free',
                      label: strings.filterFree,
                      filter: _ModelFilter.free,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.zBorder),
              Expanded(child: _body(strings)),
              if (_catalogFuture != null) _pagingBar(strings),
              Divider(height: 1, color: context.zBorder),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _customController,
                  decoration: InputDecoration(
                    hintText: strings.customModelHint,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () => _select(_customController.text),
                    ),
                  ),
                  onSubmitted: _select,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            strings.pickModel,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (_hasApiKey)
          IconButton(
            key: const Key('model-refresh-button'),
            tooltip: strings.refreshCatalog,
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _reload,
          ),
      ],
    ),
  );

  Widget _filterChip({
    required String key,
    required String label,
    required _ModelFilter filter,
  }) => ChoiceChip(
    key: Key(key),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    selected: _filter == filter,
    showCheckmark: false,
    labelPadding: const EdgeInsets.symmetric(horizontal: 10),
    visualDensity: VisualDensity.compact,
    onSelected: (bool selected) {
      if (selected) _setFilter(filter);
    },
  );

  Widget _body(AppStrings strings) {
    if (_catalogFuture == null) {
      // No API key yet: offline suggestions + hint.
      return ListView(
        children: <Widget>[
          _infoCard(icon: Icons.key_rounded, text: strings.modelsApiKeyHint),
          _suggestionList(strings),
        ],
      );
    }
    return FutureBuilder<List<RemoteModel>>(
      future: _catalogFuture,
      builder:
          (BuildContext context, AsyncSnapshot<List<RemoteModel>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              );
            }
            if (_errorMessage != null) {
              return ListView(
                children: <Widget>[
                  _errorCard(strings),
                  _suggestionList(strings),
                ],
              );
            }
            final List<RemoteModel> filtered = _applyFilters(
              snapshot.data ?? const <RemoteModel>[],
            );
            if (filtered.isEmpty) {
              return ListView(children: <Widget>[_emptyCard(strings)]);
            }
            final int pageCount = (filtered.length / modelPickerPageSize)
                .ceil();
            final int current = _page.clamp(0, pageCount - 1);
            final int start = current * modelPickerPageSize;
            final List<RemoteModel> slice = filtered
                .skip(start)
                .take(modelPickerPageSize)
                .toList();
            return ListView.builder(
              key: Key('model-list-page-$current'),
              itemCount: slice.length,
              itemBuilder: (BuildContext context, int index) =>
                  _modelTile(slice[index], strings),
            );
          },
    );
  }

  Widget _modelTile(RemoteModel model, AppStrings strings) {
    final String active = ref.watch(settingsProvider.select((s) => s.model));
    final bool selected = model.id == active;
    final List<String> meta = <String>[
      if (model.contextLength != null)
        '${(model.contextLength! / 1000).round()}k',
      if (model.supportsTools) strings.toolsBadge,
    ];
    return ListTile(
      dense: true,
      leading: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: 18,
        color: selected ? kAccentColor : context.zMuted,
      ),
      title: Text(
        model.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace'),
      ),
      subtitle: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              <String>[
                if (model.name != model.id) model.name,
                ...meta,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.zMuted),
            ),
          ),
          if (model.isFree)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: kAccentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                strings.freeBadge,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: kAccentColor,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
      onTap: () => _select(model.id),
    );
  }

  Widget _pagingBar(AppStrings strings) {
    return FutureBuilder<List<RemoteModel>>(
      future: _catalogFuture,
      builder:
          (BuildContext context, AsyncSnapshot<List<RemoteModel>> snapshot) {
            final List<RemoteModel>? data = snapshot.data;
            if (!snapshot.hasData || data == null || data.isEmpty) {
              return const SizedBox.shrink();
            }
            final int total = _applyFilters(data).length;
            if (total == 0) return const SizedBox.shrink();
            final int pageCount = (total / modelPickerPageSize).ceil();
            final int current = _page.clamp(0, pageCount - 1);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    key: const Key('model-page-first'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.first_page_rounded, size: 20),
                    onPressed: current > 0
                        ? () => setState(() => _page = 0)
                        : null,
                  ),
                  IconButton(
                    key: const Key('model-page-prev'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                    onPressed: current > 0
                        ? () => setState(() => _page = current - 1)
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      strings.pageIndicator(current + 1, pageCount),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.zMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('model-page-next'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                    onPressed: current < pageCount - 1
                        ? () => setState(() => _page = current + 1)
                        : null,
                  ),
                  IconButton(
                    key: const Key('model-page-last'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.last_page_rounded, size: 20),
                    onPressed: current < pageCount - 1
                        ? () => setState(() => _page = pageCount - 1)
                        : null,
                  ),
                ],
              ),
            );
          },
    );
  }

  Widget _suggestionList(AppStrings strings) {
    final String active = ref.watch(settingsProvider.select((s) => s.model));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            strings.suggestedFallback,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: context.zMuted,
            ),
          ),
        ),
        for (final String model in suggestedModels)
          ListTile(
            dense: true,
            leading: Icon(
              model == active
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 18,
              color: model == active ? kAccentColor : context.zMuted,
            ),
            title: Text(
              model,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
            ),
            onTap: () => _select(model),
          ),
      ],
    );
  }

  Widget _infoCard({required IconData icon, required String text}) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.zSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.zBorder),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: context.zMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: context.zMuted),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorCard(AppStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.zSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.zBorder),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, size: 18, color: context.zMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.modelsLoadError,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('model-retry-button'),
                onPressed: _reload,
                child: Text(strings.modelsRetry),
              ),
            ],
          ),
          if (_errorMessage != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _errorMessage!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: context.zMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              strings.suggestedFallbackBody,
              style: TextStyle(fontSize: 11, color: context.zMuted),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyCard(AppStrings strings) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Column(
      children: <Widget>[
        Icon(Icons.search_off_rounded, size: 32, color: context.zMuted),
        const SizedBox(height: 8),
        Text(
          strings.modelsEmpty,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          strings.modelsEmptyHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: context.zMuted),
        ),
      ],
    ),
  );
}
