import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import 'provider_models_cache.dart';

/// 生图 / 生视频页内模型选择 BottomSheet。
Future<void> showMediaModelPickerSheet({
  required BuildContext context,
  required ProviderRepository providers,
  required ProviderModelsCache modelsCache,
  required ModelKind kind,
  VoidCallback? onProviderSwitched,
}) async {
  if (kind != ModelKind.image && kind != ModelKind.video) return;
  final ready = providers.providersReadyFor(kind);
  if (ready.isEmpty) return;

  final hasCache = modelsCache.hasCached;
  final fresh = modelsCache.isFresh;
  if (!hasCache) {
    unawaited(modelsCache.load(force: false, silentRefreshIfStale: false));
  } else if (!fresh) {
    unawaited(modelsCache.load(force: false, silentRefreshIfStale: true));
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _MediaModelPickerSheet(
        providers: providers,
        modelsCache: modelsCache,
        kind: kind,
        initiallyLoading: !hasCache,
        onProviderSwitched: onProviderSwitched,
      );
    },
  );
}

class _MediaModelPickerSheet extends StatefulWidget {
  const _MediaModelPickerSheet({
    required this.providers,
    required this.modelsCache,
    required this.kind,
    required this.initiallyLoading,
    this.onProviderSwitched,
  });

  final ProviderRepository providers;
  final ProviderModelsCache modelsCache;
  final ModelKind kind;
  final bool initiallyLoading;
  final VoidCallback? onProviderSwitched;

  @override
  State<_MediaModelPickerSheet> createState() => _MediaModelPickerSheetState();
}

class _MediaModelPickerSheetState extends State<_MediaModelPickerSheet> {
  final TextEditingController _queryCtrl = TextEditingController();
  late bool _loading;
  String? _error;
  List<ProviderModelInfo> _models = const [];
  VoidCallback? _listener;

  ProviderModelsCache get _cache => widget.modelsCache;

  @override
  void initState() {
    super.initState();
    _loading = widget.initiallyLoading || _cache.loading;
    _error = _cache.error;
    _models = _cache.cachedForActive;
    _listener = _onCacheTick;
    _cache.addListener(_listener!);
  }

  void _onCacheTick() {
    if (!mounted) return;
    _syncFromCache();
  }

  void _syncFromCache() {
    final ctrlLoading = _cache.loading;
    final error = _cache.error;
    final models = _cache.cachedForActive;
    final loading = models.isEmpty
        ? (ctrlLoading || widget.initiallyLoading)
        : ctrlLoading;
    final changed = loading != _loading ||
        error != _error ||
        !_sameIds(_models, models);
    if (!changed) return;
    setState(() {
      _loading = loading;
      _error = error;
      _models = models;
    });
  }

  bool _sameIds(List<ProviderModelInfo> a, List<ProviderModelInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    final l = _listener;
    if (l != null) {
      _cache.removeListener(l);
      _listener = null;
    }
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshForce() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _cache.load(force: true, silentRefreshIfStale: false);
    if (!mounted) return;
    _syncFromCache();
  }

  Future<void> _switchProvider(ProviderConfig provider) async {
    if (provider.id == widget.providers.activeProviderId) return;
    setState(() {
      _loading = true;
      _error = null;
      _models = const [];
    });
    _queryCtrl.clear();
    await widget.providers.setActiveProvider(provider.id);
    if (!mounted) return;
    widget.onProviderSwitched?.call();
    setState(() {});
    await _cache.load(force: false, silentRefreshIfStale: false);
    if (!mounted) return;
    _syncFromCache();
  }

  String _activeModelId() {
    final p = widget.providers.activeProvider;
    if (p == null) return '';
    switch (widget.kind) {
      case ModelKind.image:
        return p.imageModel.trim();
      case ModelKind.video:
        return p.videoModel.trim();
      case ModelKind.chat:
        return p.chatModel.trim();
      case ModelKind.other:
        return '';
    }
  }

  Future<void> _pick(String modelId) async {
    final p = widget.providers.activeProvider;
    if (p == null) return;
    final id = modelId.trim();
    if (id.isEmpty) return;
    if (widget.kind == ModelKind.image) {
      await widget.providers.updateProvider(p.id, imageModel: id);
    } else if (widget.kind == ModelKind.video) {
      await widget.providers.updateProvider(p.id, videoModel: id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  String get _title {
    switch (widget.kind) {
      case ModelKind.image:
        return '选择生图模型';
      case ModelKind.video:
        return '选择视频模型';
      case ModelKind.chat:
      case ModelKind.other:
        return '选择模型';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final media = MediaQuery.of(context);
    final readyProviders = widget.providers.providersReadyFor(widget.kind);
    final activeId = widget.providers.activeProviderId;
    final current = _activeModelId();
    final options = modelOptionsByKind(
      _models,
      widget.kind,
      current: current,
    );
    final q = _queryCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? options
        : [
            for (final o in options)
              if (o.value.toLowerCase().contains(q) ||
                  o.label.toLowerCase().contains(q))
                o,
          ];
    final activeReady = readyProviders.any((p) => p.id == activeId);
    final showProviders =
        readyProviders.length > 1 || (readyProviders.isNotEmpty && !activeReady);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          height: media.size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新模型列表',
                      onPressed: _loading ? null : _refreshForce,
                      icon: _loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tokens.primary,
                              ),
                            )
                          : Icon(Icons.refresh, color: tokens.inkSecondary),
                    ),
                  ],
                ),
              ),
              if (showProviders) ...[
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: readyProviders.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final p = readyProviders[index];
                      final selected = p.id == activeId;
                      return ChoiceChip(
                        label: Text(p.name),
                        selected: selected,
                        onSelected: _loading
                            ? null
                            : (_) => _switchProvider(p),
                        avatar: p.lastTestOk == null
                            ? null
                            : Icon(
                                Icons.circle,
                                size: 8,
                                color: p.lastTestOk!
                                    ? tokens.success
                                    : tokens.danger,
                              ),
                      );
                    },
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _queryCtrl,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    color: tokens.ink,
                  ).withMonoFont(tokens),
                  decoration: InputDecoration(
                    hintText: options.isEmpty ? '先拉取模型…' : '搜索模型…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.danger,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Text(
                          _loading
                              ? '加载中…'
                              : (q.isEmpty
                                  ? '无可用模型，点击刷新拉取'
                                  : '无匹配「${_queryCtrl.text.trim()}」'),
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.inkMuted,
                            fontFamily: tokens.fontFamily,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final o = filtered[index];
                          final active = o.value == current;
                          return ListTile(
                            selected: active,
                            selectedTileColor:
                                tokens.primary.withValues(alpha: 0.10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            title: Text(
                              o.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: o.manual
                                  ? TextStyle(
                                      fontSize: 14,
                                      color: tokens.inkMuted,
                                      fontFamily: tokens.fontFamily,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    )
                                  : TextStyle(
                                      fontSize: 14,
                                      color: tokens.ink,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ).withMonoFont(tokens),
                            ),
                            trailing: active
                                ? Icon(Icons.check, color: tokens.primary)
                                : null,
                            onTap: () => _pick(o.value),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
