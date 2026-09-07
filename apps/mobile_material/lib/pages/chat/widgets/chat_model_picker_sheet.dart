import 'dart:async';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';

/// M-ModelPicker：顶栏入口打开的可搜索模型 BottomSheet（CHAT-MODEL）。
Future<void> showChatModelPickerSheet({
  required BuildContext context,
  required ChatController controller,
}) async {
  final creds = controller.providers.activeChatCredentials;
  if (creds == null) return;

  final hasCache = controller.hasCachedChatModels;
  final fresh = controller.isChatModelsCacheFresh;
  if (!hasCache) {
    unawaited(
      controller.loadChatModels(force: false, silentRefreshIfStale: false),
    );
  } else if (!fresh) {
    unawaited(
      controller.loadChatModels(force: false, silentRefreshIfStale: true),
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _ChatModelPickerSheet(
        controller: controller,
        initiallyLoading: !hasCache,
      );
    },
  );
}

class _ChatModelPickerSheet extends StatefulWidget {
  const _ChatModelPickerSheet({
    required this.controller,
    required this.initiallyLoading,
  });

  final ChatController controller;
  final bool initiallyLoading;

  @override
  State<_ChatModelPickerSheet> createState() => _ChatModelPickerSheetState();
}

class _ChatModelPickerSheetState extends State<_ChatModelPickerSheet> {
  final TextEditingController _queryCtrl = TextEditingController();
  late bool _loading;
  String? _error;
  List<ProviderModelInfo> _models = const [];
  VoidCallback? _listener;

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
      _ctrl.removeListener(l);
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
    await _ctrl.loadChatModels(force: true, silentRefreshIfStale: false);
    if (!mounted) return;
    _syncFromCtrl();
  }

  Future<void> _pick(String modelId) async {
    final p = _repo.activeProvider;
    if (p == null) return;
    await _repo.updateProvider(p.id, chatModel: modelId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final media = MediaQuery.of(context);
    final creds = _repo.activeChatCredentials;
    final current = creds?.chatModel ?? '';
    final options = modelOptionsByKind(
      _models,
      ModelKind.chat,
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
                        '选择对话模型',
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
