import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/filterable_model_picker.dart';

/// M-ProviderForm：提供商编辑 BottomSheet（SET-PROVIDER-EDIT），底栏固定保存/取消。
Future<void> showProviderEditSheet({
  required BuildContext context,
  required ProviderRepository repository,
  required String providerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      return _ProviderEditSheet(
        repository: repository,
        providerId: providerId,
      );
    },
  );
}

class _ProviderEditSheet extends StatefulWidget {
  const _ProviderEditSheet({
    required this.repository,
    required this.providerId,
  });

  final ProviderRepository repository;
  final String providerId;

  @override
  State<_ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends State<_ProviderEditSheet> {
  late String _providerId;
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _chatModelCtrl = TextEditingController();
  final _imageModelCtrl = TextEditingController();
  final _videoModelCtrl = TextEditingController();
  ProviderType _type = ProviderType.openaiCompatible;
  bool _obscureKey = true;
  bool _testing = false;
  bool _listingModels = false;
  String? _statusText;
  bool _statusOk = false;
  List<ProviderModelInfo> _modelHints = const [];
  bool _dirty = false;
  bool _syncingForm = false;

  ProviderRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _providerId = widget.providerId;
    _repo.addListener(_onRepoChanged);
    _baseUrlCtrl.addListener(_onProbeFieldsChanged);
    _apiKeyCtrl.addListener(_onProbeFieldsChanged);
    _loadFormFromSelected();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _baseUrlCtrl.removeListener(_onProbeFieldsChanged);
    _apiKeyCtrl.removeListener(_onProbeFieldsChanged);
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _chatModelCtrl.dispose();
    _imageModelCtrl.dispose();
    _videoModelCtrl.dispose();
    super.dispose();
  }

  void _onProbeFieldsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final exists = _repo.providers.any((p) => p.id == _providerId);
    if (!exists) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  ProviderConfig? get _selected {
    for (final p in _repo.providers) {
      if (p.id == _providerId) return p;
    }
    return null;
  }

  void _loadFormFromSelected() {
    final p = _selected;
    _syncingForm = true;
    if (p == null) {
      _nameCtrl.clear();
      _baseUrlCtrl.clear();
      _apiKeyCtrl.clear();
      _chatModelCtrl.clear();
      _imageModelCtrl.clear();
      _videoModelCtrl.clear();
      _type = ProviderType.openaiCompatible;
      _statusText = null;
      _modelHints = const [];
      _dirty = false;
    } else {
      _nameCtrl.text = p.name;
      _baseUrlCtrl.text = p.baseUrl;
      _apiKeyCtrl.text = p.apiKey;
      _chatModelCtrl.text = p.chatModel;
      _imageModelCtrl.text = p.imageModel;
      _videoModelCtrl.text = p.videoModel;
      _type = p.type;
      if (p.lastTestDetail != null) {
        _statusText = p.lastTestDetail;
        _statusOk = p.lastTestOk == true;
      } else {
        _statusText = null;
      }
      _modelHints = const [];
      _dirty = false;
    }
    _syncingForm = false;
  }

  void _markDirty() {
    if (_syncingForm || _dirty) return;
    setState(() => _dirty = true);
  }

  List<ModelSelectOption> _stableOptions(ModelKind kind, String committed) {
    return modelOptionsByKind(_modelHints, kind, current: committed);
  }

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? materialTokensOf(context).danger : null,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '放弃未保存更改？',
      message: '当前表单有未保存修改，关闭将丢失这些更改。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃',
    );
    return ok;
  }

  Future<void> _tryClose() async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (!discard) return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<bool> _save() async {
    final current = _selected;
    if (current == null) return false;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写显示名称', error: true);
      return false;
    }
    final baseUrl = _baseUrlCtrl.text.trim();
    final urlRisk = warnUnsafeUrl(baseUrl);
    final next = current.copyWith(
      name: name,
      type: _type,
      baseUrl: baseUrl,
      apiKey: _apiKeyCtrl.text,
      chatModel: _chatModelCtrl.text.trim(),
      imageModel: _imageModelCtrl.text.trim(),
      videoModel: _videoModelCtrl.text.trim(),
    );
    try {
      await _repo.saveProvider(next);
    } on UrlSafetyException catch (e) {
      _snack(e.message, error: true);
      return false;
    }
    if (!mounted) return false;
    setState(() {
      _dirty = false;
      _loadFormFromSelected();
    });
    _snack('已保存');
    if (urlRisk != null) {
      _snack(urlRisk);
    }
    return true;
  }

  void _cancelEdits() {
    setState(_loadFormFromSelected);
  }

  Future<void> _delete() async {
    final current = _selected;
    if (current == null) return;
    if (current.builtin) {
      _snack('内置提供商不可删除', error: true);
      return;
    }
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除此提供商？',
      message: '将删除「${current.name}」及其本机密钥，此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!ok) return;
    final removed = await _repo.removeProvider(current.id);
    if (!removed) {
      _snack('无法删除（至少保留一个提供商）', error: true);
      return;
    }
    if (!mounted) return;
    _snack('已删除');
    Navigator.of(context).pop();
  }

  bool get _canProbeConnection {
    return _baseUrlCtrl.text.trim().isNotEmpty &&
        _apiKeyCtrl.text.trim().isNotEmpty;
  }

  String? get _probeBlockReason {
    if (_baseUrlCtrl.text.trim().isEmpty) return '请先填写 Base URL';
    if (_apiKeyCtrl.text.trim().isEmpty) return '请先填写 API Key';
    return null;
  }

  Future<void> _testConnection() async {
    final current = _selected;
    if (current == null) return;
    final blocked = _probeBlockReason;
    if (blocked != null) {
      _snack(blocked, error: true);
      return;
    }
    if (_dirty) {
      final saved = await _save();
      if (!saved) return;
    }
    setState(() {
      _testing = true;
      _statusText = '测试中…';
      _statusOk = false;
    });
    try {
      final result = await _repo.testConnection(current.id);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusOk = result.ok;
        _statusText = result.latencyMs != null
            ? '${result.detail} · ${result.latencyMs} ms'
            : result.detail;
        if (result.models.isNotEmpty) {
          _modelHints = result.models;
        }
      });
      _snack(result.detail, error: !result.ok);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusOk = false;
        _statusText = e.toString();
      });
      _snack('测试失败：$e', error: true);
    }
  }

  Future<void> _pullModels() async {
    final current = _selected;
    if (current == null) return;
    final blocked = _probeBlockReason;
    if (blocked != null) {
      _snack(blocked, error: true);
      return;
    }
    if (_dirty) {
      final saved = await _save();
      if (!saved) return;
    }
    setState(() => _listingModels = true);
    try {
      final models = await _repo.listModels(current.id);
      if (!mounted) return;
      setState(() {
        _listingModels = false;
        _modelHints = models;
        _statusOk = true;
        _statusText = '已拉取 ${models.length} 个模型';
      });
      _snack('模型列表已刷新');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listingModels = false;
        _statusOk = false;
        _statusText = e.toString();
      });
      _snack('拉取失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final selected = _selected;
    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * 0.92;

    if (selected == null) {
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _tryClose();
      },
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '编辑提供商',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _tryClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Text(
                      '基本信息',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '显示名称',
                        hintText: '例如 OpenAI 兼容 · 自建',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ProviderType>(
                      key: ValueKey(_type),
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: [
                        for (final t in ProviderType.values)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _type = v;
                          _dirty = true;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'https://api.example.com/v1',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyCtrl,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-…',
                        suffixIcon: IconButton(
                          tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscureKey = !_obscureKey),
                        ),
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '连接与模型',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: (!_canProbeConnection || _testing)
                                ? null
                                : _testConnection,
                            child: Text(_testing ? '测试中…' : '测试连接'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                (!_canProbeConnection || _listingModels)
                                    ? null
                                    : _pullModels,
                            child:
                                Text(_listingModels ? '拉取中…' : '拉取模型'),
                          ),
                        ),
                      ],
                    ),
                    if (!_canProbeConnection)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '需先填写 Base URL 与 API Key',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkMuted,
                          ),
                        ),
                      )
                    else if (_statusText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '● $_statusText',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                _statusOk ? tokens.success : tokens.danger,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      '对话模型',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilterableModelPicker(
                      controller: _chatModelCtrl,
                      options: _stableOptions(
                        ModelKind.chat,
                        selected.chatModel,
                      ),
                      placeholder: 'gpt-4o / grok-4.5',
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '生图模型',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilterableModelPicker(
                      controller: _imageModelCtrl,
                      options: _stableOptions(
                        ModelKind.image,
                        selected.imageModel,
                      ),
                      placeholder: 'gpt-image-1 / grok-imagine-image',
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '视频模型',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilterableModelPicker(
                      controller: _videoModelCtrl,
                      options: _stableOptions(
                        ModelKind.video,
                        selected.videoModel,
                      ),
                      placeholder: 'sora-2 / grok-imagine-video',
                      allowClear: true,
                      clearLabel: '不使用',
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '先「拉取模型」；列表可搜索筛选。密钥仅存本机；视频可清空表示不使用。',
                      style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                    ),
                    if (!selected.builtin) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.danger,
                          ),
                          child: const Text('删除此提供商…'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Material(
                elevation: 6,
                color: tokens.surface,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _dirty
                                ? () async {
                                    final nav = Navigator.of(context);
                                    final ok = await _save();
                                    if (ok && mounted) nav.pop();
                                  }
                                : null,
                            child: const Text('保存'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _dirty ? _cancelEdits : _tryClose,
                            child: Text(_dirty ? '取消' : '关闭'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
