import 'dart:async';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../chat_controller.dart';

/// F-ModelCombo：CommandBar 可搜索模型下拉（CHAT-MODEL）。
///
/// 优先使用 [ChatController] 级缓存；打开时立刻 showFlyout，无缓存显示骨架，
/// TTL 过期才后台静默刷新。Flyout 内用局部 setState，不挂 ChatController。
class ChatModelCombo extends StatefulWidget {
  const ChatModelCombo({
    super.key,
    required this.controller,
  });

  final ChatController controller;

  @override
  State<ChatModelCombo> createState() => _ChatModelComboState();
}

class _ChatModelComboState extends State<ChatModelCombo> {
  final FlyoutController _flyout = FlyoutController();
  final TextEditingController _queryCtrl = TextEditingController();

  ChatController get _ctrl => widget.controller;

  ProviderRepository get _repo => _ctrl.providers;

  @override
  void dispose() {
    _flyout.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    _queryCtrl.clear();
    if (!mounted) return;

    final hasCache = _ctrl.hasCachedChatModels;
    final fresh = _ctrl.isChatModelsCacheFresh;

    if (!hasCache) {
      unawaited(
        _ctrl.loadChatModels(force: false, silentRefreshIfStale: false),
      );
    } else if (!fresh) {
      unawaited(
        _ctrl.loadChatModels(force: false, silentRefreshIfStale: true),
      );
    }

    await _flyout.showFlyout<void>(
      barrierDismissible: true,
      dismissWithEsc: true,
      placementMode: FlyoutPlacementMode.bottomLeft,
      transitionDuration: const Duration(milliseconds: 80),
      builder: (ctx) => _ModelComboFlyout(
        controller: _ctrl,
        queryCtrl: _queryCtrl,
        initiallyLoading: !hasCache,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final readyProviders = _repo.providersReadyFor(ModelKind.chat);
    final creds = _repo.activeChatCredentials;
    final ready = readyProviders.isNotEmpty;
    final String label;
    if (creds != null) {
      label = '${creds.providerName} · ${creds.chatModel}';
    } else if (ready) {
      label = '选择提供商';
    } else {
      label = '未配置模型';
    }

    return FlyoutTarget(
      controller: _flyout,
      child: HoverButton(
        onPressed: ready ? _open : null,
        cursor: ready
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        builder: (context, states) {
          final hovered = states.isHovered || states.isPressed;
          return Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hovered
                    ? Color.lerp(tokens.primary, tokens.border, 0.55)!
                    : tokens.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ready ? tokens.success : tokens.inkMuted,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkSecondary,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
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
    );
  }
}

/// Flyout 内容：本地状态 + 短轮询/一次性监听加载结果，不挂整树 ListenableBuilder。
class _ModelComboFlyout extends StatefulWidget {
  const _ModelComboFlyout({
    required this.controller,
    required this.queryCtrl,
    required this.initiallyLoading,
  });

  final ChatController controller;
  final TextEditingController queryCtrl;
  final bool initiallyLoading;

  @override
  State<_ModelComboFlyout> createState() => _ModelComboFlyoutState();
}

class _ModelComboFlyoutState extends State<_ModelComboFlyout> {
  late bool _loading;
  String? _error;
  List<ProviderModelInfo> _models = const [];
  VoidCallback? _listener;
  Timer? _poll;

  ChatController get _ctrl => widget.controller;

  ProviderRepository get _repo => _ctrl.providers;

  @override
  void initState() {
    super.initState();
    _loading = widget.initiallyLoading || _ctrl.modelsLoading;
    _error = _ctrl.modelsError;
    _models = _ctrl.cachedChatModels;
    _listener = _onCtrlTick;
    _ctrl.addListener(_listener!);
    if (_loading || _models.isEmpty) {
      _poll = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted) return;
        _syncFromCtrl();
      });
    }
  }

  void _onCtrlTick() {
    if (!mounted) return;
    _syncFromCtrl();
  }

  void _syncFromCtrl() {
    final ctrlLoading = _ctrl.modelsLoading;
    final error = _ctrl.modelsError;
    final models = _ctrl.cachedChatModels;
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
      _ctrl.removeListener(l);
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
    await _ctrl.loadChatModels(force: true, silentRefreshIfStale: false);
    if (!mounted) return;
    _syncFromCtrl();
  }

  Future<void> _switchProvider(ProviderConfig provider) async {
    if (provider.id == _repo.activeProviderId) return;
    setState(() {
      _loading = true;
      _error = null;
      _models = const [];
    });
    widget.queryCtrl.clear();
    await _repo.setActiveProvider(provider.id);
    if (!mounted) return;
    setState(() {});
    await _ctrl.loadChatModels(force: false, silentRefreshIfStale: false);
    if (!mounted) return;
    _syncFromCtrl();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final readyProviders = _repo.providersReadyFor(ModelKind.chat);
    final creds = _repo.activeChatCredentials;
    final current = creds?.chatModel ?? '';
    final activeId = _repo.activeProviderId;
    final options = modelOptionsByKind(
      _models,
      ModelKind.chat,
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
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 420),
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
                    placeholder:
                        options.isEmpty ? '先拉取模型…' : '搜索模型…',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: '刷新模型列表',
                  child: IconButton(
                    icon: _loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: ProgressRing(strokeWidth: 1.5),
                          )
                        : const Icon(
                            FluentIcons.refresh,
                            size: 12,
                          ),
                    onPressed: _loading ? null : _refreshForce,
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
            height: 280,
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
                        onPressed: () async {
                          final p = _repo.activeProvider;
                          if (p == null) return;
                          await _repo.updateProvider(
                            p.id,
                            chatModel: o.value,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
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
