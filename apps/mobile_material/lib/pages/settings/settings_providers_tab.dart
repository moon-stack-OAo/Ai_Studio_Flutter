import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/filterable_model_picker.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';

class SettingsProvidersTab extends StatefulWidget {
  const SettingsProvidersTab({
    super.key,
    required this.repository,
  });

  final ProviderRepository repository;

  @override
  State<SettingsProvidersTab> createState() => _SettingsProvidersTabState();
}

class _SettingsProvidersTabState extends State<SettingsProvidersTab> {
  String? _selectedId;
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
  bool _formExpanded = true;

  ProviderRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _baseUrlCtrl.addListener(_onProbeFieldsChanged);
    _apiKeyCtrl.addListener(_onProbeFieldsChanged);
    _selectedId = _repo.activeProviderId;
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
    final exists = _repo.providers.any((p) => p.id == _selectedId);
    if (!exists) {
      _selectedId = _repo.activeProviderId;
      _loadFormFromSelected();
    }
    setState(() {});
  }

  ProviderConfig? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _repo.providers) {
      if (p.id == id) return p;
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

  Future<void> _selectProvider(String id) async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    setState(() {
      _selectedId = id;
      _formExpanded = true;
      _loadFormFromSelected();
    });
    await _repo.setActiveProvider(id);
  }

  Future<bool?> _confirmDiscard() async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '放弃未保存更改？',
      message: '当前表单有未保存修改，切换提供商将丢失这些更改。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃',
    );
    return ok;
  }

  Future<void> _addProvider() async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    final created = await _repo.addProvider();
    setState(() {
      _selectedId = created.id;
      _formExpanded = true;
      _loadFormFromSelected();
    });
    _snack('已添加自定义提供商');
  }

  Future<void> _save() async {
    final current = _selected;
    if (current == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写显示名称', error: true);
      return;
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
      return;
    }
    setState(() {
      _dirty = false;
      _loadFormFromSelected();
    });
    _snack('已保存');
    if (urlRisk != null) {
      _snack(urlRisk);
    }
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
    setState(() {
      _selectedId = _repo.activeProviderId;
      _loadFormFromSelected();
    });
    _snack('已删除');
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
    if (_dirty) await _save();
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
    if (_dirty) await _save();
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
    final providers = _repo.providers;
    final selected = _selected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
          '点选一项展开编辑',
          style: TextStyle(fontSize: 12, color: tokens.inkMuted),
        ),
        const SizedBox(height: 8),
        if (providers.isEmpty)
          MaterialProvidersListEmpty(
            onAdd: _addProvider,
            illustration: const MaterialEmptyIllustration.noProviders(),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < providers.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: tokens.border),
                  _ProviderListTile(
                    provider: providers[i],
                    selected: providers[i].id == _selectedId,
                    onTap: () => _selectProvider(providers[i].id),
                  ),
                ],
              ],
            ),
          ),
        if (selected != null && _formExpanded) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '编辑提供商',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: tokens.ink,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _formExpanded = false),
                        child: const Text('收起'),
                      ),
                    ],
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            (!_canProbeConnection || _testing) ? null : _testConnection,
                        child: Text(_testing ? '测试中…' : '测试连接'),
                      ),
                      OutlinedButton(
                        onPressed: (!_canProbeConnection || _listingModels)
                            ? null
                            : _pullModels,
                        child: Text(_listingModels ? '拉取中…' : '拉取模型'),
                      ),
                      FilledButton(
                        onPressed: _dirty ? _save : null,
                        child: const Text('保存'),
                      ),
                      if (_dirty)
                        TextButton(
                          onPressed: _cancelEdits,
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                  if (!_canProbeConnection)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '需先填写 Base URL 与 API Key',
                        style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                      ),
                    )
                  else if (_statusText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '● $_statusText',
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusOk ? tokens.success : tokens.danger,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
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
                      _selected?.chatModel ?? '',
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
                      _selected?.imageModel ?? '',
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
                      _selected?.videoModel ?? '',
                    ),
                    placeholder: 'sora-2 / grok-imagine-video',
                    allowClear: true,
                    clearLabel: '不使用',
                    onChanged: (_) => _markDirty(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '密钥仅存本机 Keystore / Keychain。视频可清空表示不使用。',
                    style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                  ),
                  if (!selected.builtin) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _delete,
                      style: TextButton.styleFrom(foregroundColor: tokens.danger),
                      child: const Text('删除此提供商…'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addProvider,
          icon: const Icon(Icons.add),
          label: const Text('添加提供商'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            side: BorderSide(
              color: tokens.border,
              style: BorderStyle.solid,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final ProviderConfig provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);

    late final String pill;
    late final Color pillFg;
    late final Color pillBg;
    if (provider.lastTestOk == true) {
      pill = '已连接';
      pillFg = tokens.success;
      pillBg = Color.lerp(tokens.success, tokens.surface, 0.88)!;
    } else if (provider.lastTestOk == false) {
      pill = '失败';
      pillFg = tokens.danger;
      pillBg = Color.lerp(tokens.danger, tokens.surface, 0.9)!;
    } else if (!provider.hasApiKey) {
      pill = '待配置';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    } else {
      pill = '待测试';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    }

    final meta = provider.baseUrl.trim().isNotEmpty
        ? provider.baseUrl.trim()
        : (provider.builtin ? '预设 · Key 掩码' : '未填写 Base URL');

    final initial = provider.name.trim().isEmpty
        ? '?'
        : provider.name.trim().characters.take(2).toString();

    return Material(
      color: selected
          ? Color.lerp(tokens.primary, tokens.surface, 0.88)
          : tokens.surface,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected)
                Container(width: 3, color: tokens.primary)
              else
                const SizedBox(width: 3),
              Expanded(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: tokens.surfaceMuted,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.primaryPressed,
                      ),
                    ),
                  ),
                  title: Text(
                    provider.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                    ),
                  ),
                  subtitle: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Color.lerp(pillFg, tokens.border, 0.55)!,
                      ),
                    ),
                    child: Text(
                      pill,
                      style: TextStyle(fontSize: 10, color: pillFg),
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
