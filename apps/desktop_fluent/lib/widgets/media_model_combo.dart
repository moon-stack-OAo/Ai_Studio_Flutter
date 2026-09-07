import 'dart:async';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'provider_models_cache.dart';

/// 生图 / 生视频侧栏模型下拉（可搜索 + 刷新）。
///
/// 交互对齐 [ChatModelCombo]：Flyout + TTL 缓存，打开不阻塞 UI。
class MediaModelCombo extends StatefulWidget {
  const MediaModelCombo({
    super.key,
    required this.providers,
    required this.modelsCache,
    required this.kind,
    required this.currentModel,
    required this.enabled,
    this.placeholder = '未配置',
    this.onProviderSwitched,
  });

  final ProviderRepository providers;
  final ProviderModelsCache modelsCache;
  final ModelKind kind;
  final String currentModel;
  final bool enabled;
  final String placeholder;
  final VoidCallback? onProviderSwitched;

  @override
  State<MediaModelCombo> createState() => _MediaModelComboState();
}

class _MediaModelComboState extends State<MediaModelCombo> {
  final FlyoutController _flyout = FlyoutController();
  final TextEditingController _queryCtrl = TextEditingController();

  @override
  void dispose() {
    _flyout.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!widget.enabled) return;
    _queryCtrl.clear();
    if (!mounted) return;

    final cache = widget.modelsCache;
    final hasCache = cache.hasCached;
    final fresh = cache.isFresh;

    if (!hasCache) {
      unawaited(cache.load(force: false, silentRefreshIfStale: false));
    } else if (!fresh) {
      unawaited(cache.load(force: false, silentRefreshIfStale: true));
    }

    await _flyout.showFlyout<void>(
      barrierDismissible: true,
      dismissWithEsc: true,
      placementMode: FlyoutPlacementMode.bottomLeft,
      transitionDuration: const Duration(milliseconds: 80),
      builder: (ctx) => _MediaModelFlyout(
        providers: widget.providers,
        modelsCache: cache,
        kind: widget.kind,
        currentModel: widget.currentModel,
        queryCtrl: _queryCtrl,
        initiallyLoading: !hasCache,
        onProviderSwitched: widget.onProviderSwitched,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final readyProviders = widget.providers.providersReadyFor(widget.kind);
    final active = widget.providers.activeProvider;
    final model = widget.currentModel.trim();
    final String label;
    if (model.isNotEmpty && active != null) {
      label = readyProviders.length > 1
          ? '${active.name} · $model'
          : model;
    } else if (model.isNotEmpty) {
      label = model;
    } else {
      label = widget.placeholder;
    }
    final ready = widget.enabled && readyProviders.isNotEmpty;
    final readyLabel = ready ? '模型已就绪' : '模型未就绪';

    return FlyoutTarget(
      controller: _flyout,
      child: Tooltip(
        message: '$label，$readyLabel',
        child: Semantics(
          button: true,
          enabled: ready,
          label: '选择模型，$label，$readyLabel',
          excludeSemantics: true,
          child: HoverButton(
            onPressed: ready ? _open : null,
            cursor:
                ready ? SystemMouseCursors.click : SystemMouseCursors.basic,
            builder: (context, states) {
              final hovered = states.isHovered || states.isPressed;
              return Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: hovered && ready
                        ? Color.lerp(tokens.primary, tokens.border, 0.55)!
                        : tokens.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: ready ? tokens.ink : tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      FluentIcons.chevron_down,
                      size: 10,
                      color: tokens.inkMuted,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MediaModelFlyout extends StatefulWidget {
  const _MediaModelFlyout({
    required this.providers,
    required this.modelsCache,
    required this.kind,
    required this.currentModel,
    required this.queryCtrl,
    required this.initiallyLoading,
    this.onProviderSwitched,
  });

  final ProviderRepository providers;
  final ProviderModelsCache modelsCache;
  final ModelKind kind;
  final String currentModel;
  final TextEditingController queryCtrl;
  final bool initiallyLoading;
  final VoidCallback? onProviderSwitched;

  @override
  State<_MediaModelFlyout> createState() => _MediaModelFlyoutState();
}

class _MediaModelFlyoutState extends State<_MediaModelFlyout> {
  late bool _loading;
  String? _error;
  List<ProviderModelInfo> _models = const [];
  VoidCallback? _listener;
  Timer? _poll;

  ProviderModelsCache get _cache => widget.modelsCache;

  @override
  void initState() {
    super.initState();
    _loading = widget.initiallyLoading || _cache.loading;
    _error = _cache.error;
    _models = _cache.cachedForActive;
    _listener = _onCacheTick;
    _cache.addListener(_listener!);
    if (_loading || _models.isEmpty) {
      _poll = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted) return;
        _syncFromCache();
      });
    }
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
    if (changed) {
      setState(() {
        _loading = loading;
        _error = error;
        _models = models;
      });
    }
    if (!ctrlLoading && _models.isNotEmpty) {
      _poll?.cancel();
      _poll = null;
    }
  }

  bool _sameIds(List<ProviderModelInfo> a, List<ProviderModelInfo> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _detachListener() {
    final l = _listener;
    if (l != null) {
      _cache.removeListener(l);
      _listener = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _detachListener();
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
    widget.queryCtrl.clear();
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
    if (p == null) return widget.currentModel.trim();
    switch (widget.kind) {
      case ModelKind.image:
        return p.imageModel.trim();
      case ModelKind.video:
        return p.videoModel.trim();
      case ModelKind.chat:
        return p.chatModel.trim();
      case ModelKind.other:
        return widget.currentModel.trim();
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
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final readyProviders = widget.providers.providersReadyFor(widget.kind);
    final activeId = widget.providers.activeProviderId;
    final current = _activeModelId();
    final options = modelOptionsByKind(
      _models,
      widget.kind,
      current: current,
    );
    final q = widget.queryCtrl.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? options
        : [
            for (final o in options)
              if (o.value.toLowerCase().contains(q) ||
                  o.label.toLowerCase().contains(q))
                o,
          ];

    final borderColor = Color.lerp(tokens.border, tokens.ink, 0.12)!;
    final activeReady =
        readyProviders.any((p) => p.id == activeId);
    final showProviders =
        readyProviders.length > 1 || (readyProviders.isNotEmpty && !activeReady);

    return FlyoutContent(
      padding: EdgeInsets.zero,
      color: tokens.surfaceElevated,
      useAcrylic: false,
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 380),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showProviders) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                '提供商',
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: readyProviders.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final p = readyProviders[index];
                  final selected = p.id == activeId;
                  return HoverButton(
                    onPressed: _loading ? null : () => _switchProvider(p),
                    cursor: SystemMouseCursors.click,
                    builder: (context, states) {
                      final hovered =
                          states.isHovered || states.isPressed;
                      final bg = selected
                          ? tokens.primary.withValues(alpha: 0.14)
                          : hovered
                              ? tokens.ink.withValues(alpha: 0.06)
                              : tokens.surfaceMuted;
                      final fg = selected || hovered
                          ? tokens.ink
                          : tokens.inkSecondary;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? tokens.primary.withValues(alpha: 0.45)
                                : tokens.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.lastTestOk != null) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p.lastTestOk!
                                      ? tokens.success
                                      : tokens.danger,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: fg,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Divider(
                style: DividerThemeData(
                  decoration: BoxDecoration(color: tokens.border),
                  horizontalMargin: EdgeInsets.zero,
                  verticalMargin: EdgeInsets.zero,
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: widget.queryCtrl,
                    placeholder: options.isEmpty ? '先拉取模型…' : '搜索模型…',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '刷新模型列表',
                  child: Semantics(
                    button: true,
                    label: '刷新模型列表',
                    excludeSemantics: true,
                    child: IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 1.5),
                            )
                          : const Icon(FluentIcons.refresh, size: 12),
                      onPressed: _loading ? null : _refreshForce,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            style: DividerThemeData(
              decoration: BoxDecoration(color: tokens.border),
              horizontalMargin: EdgeInsets.zero,
              verticalMargin: EdgeInsets.zero,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.danger,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
          SizedBox(
            height: 240,
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: Text(
                      _loading
                          ? '加载中…'
                          : (q.isEmpty
                              ? '无可用模型，点击刷新拉取'
                              : '无匹配「${widget.queryCtrl.text.trim()}」'),
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final o = filtered[index];
                      final active = o.value == current;
                      return HoverButton(
                        onPressed: () => _pick(o.value),
                        builder: (context, states) {
                          final hovered =
                              states.isHovered || states.isPressed;
                          final bg = active
                              ? tokens.primary.withValues(alpha: 0.14)
                              : hovered
                                  ? tokens.ink.withValues(alpha: 0.06)
                                  : Colors.transparent;
                          final fg = active || hovered
                              ? tokens.ink
                              : tokens.inkSecondary;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              o.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: o.manual ? tokens.inkMuted : fg,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ).withMonoFont(tokens),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
