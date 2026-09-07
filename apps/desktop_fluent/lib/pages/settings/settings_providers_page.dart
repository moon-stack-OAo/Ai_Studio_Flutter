import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/filterable_model_picker.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/fluent_empty_states.dart';

class SettingsProvidersPage extends StatefulWidget {
  const SettingsProvidersPage({
    super.key,
    required this.repository,
  });

  final ProviderRepository repository;

  @override
  State<SettingsProvidersPage> createState() => _SettingsProvidersPageState();
}

class _SettingsProvidersPageState extends State<SettingsProvidersPage> {
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
    final exists =
        _repo.providers.any((p) => p.id == _selectedId);
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
    // 已脏则不再 setState，避免 AutoSuggest 每键重建整页语义树
    setState(() => _dirty = true);
  }

  /// 模型下拉 options：只依赖已拉取列表 + 当前已提交值，不跟输入逐字变。
  List<ModelSelectOption> _stableOptions(ModelKind kind, String committed) {
    return modelOptionsByKind(_modelHints, kind, current: committed);
  }

  Future<void> _selectProvider(String id) async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    setState(() {
      _selectedId = id;
      _loadFormFromSelected();
    });
    await _repo.setActiveProvider(id);
  }

  Future<bool?> _confirmDiscard() async {
    final ok = await showFluentConfirmDialog(
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
      _loadFormFromSelected();
    });
    _showInfoBar('已添加自定义提供商', InfoBarSeverity.success);
  }

  Future<void> _save() async {
    final current = _selected;
    if (current == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showInfoBar('请填写显示名称', InfoBarSeverity.warning);
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
      _showInfoBar(e.message, InfoBarSeverity.error);
      return;
    }
    setState(() {
      _dirty = false;
      _loadFormFromSelected();
    });
    _showInfoBar('已保存', InfoBarSeverity.success);
    if (urlRisk != null) {
      _showInfoBar(urlRisk, InfoBarSeverity.warning);
    }
  }

  void _cancelEdits() {
    setState(_loadFormFromSelected);
  }

  Future<void> _delete() async {
    final current = _selected;
    if (current == null) return;
    if (current.builtin) {
      _showInfoBar('内置提供商不可删除', InfoBarSeverity.warning);
      return;
    }
    final ok = await showFluentConfirmDialog(
      context: context,
      title: '删除此提供商？',
      message: '将删除「${current.name}」及其本机密钥，此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!ok) return;
    final removed = await _repo.removeProvider(current.id);
    if (!removed) {
      _showInfoBar('无法删除（至少保留一个提供商）', InfoBarSeverity.warning);
      return;
    }
    setState(() {
      _selectedId = _repo.activeProviderId;
      _loadFormFromSelected();
    });
    _showInfoBar('已删除', InfoBarSeverity.success);
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
      _showInfoBar(blocked, InfoBarSeverity.warning);
      return;
    }
    if (_dirty) {
      await _save();
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
      _showInfoBar(
        result.ok ? (result.detail) : result.detail,
        result.ok ? InfoBarSeverity.success : InfoBarSeverity.error,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _statusOk = false;
        _statusText = e.toString();
      });
      _showInfoBar('测试失败：$e', InfoBarSeverity.error);
    }
  }

  Future<void> _pullModels() async {
    final current = _selected;
    if (current == null) return;
    final blocked = _probeBlockReason;
    if (blocked != null) {
      _showInfoBar(blocked, InfoBarSeverity.warning);
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
      _showInfoBar('模型列表已刷新', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listingModels = false;
        _statusOk = false;
        _statusText = e.toString();
      });
      _showInfoBar('拉取失败：$e', InfoBarSeverity.error);
    }
  }

  void _showInfoBar(String message, InfoBarSeverity severity) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(message),
          severity: severity,
          onClose: close,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final providers = _repo.providers;
    final selected = _selected;

    return ColoredBox(
      color: tokens.canvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.canvas,
                border: Border(right: BorderSide(color: tokens.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '提供商',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: tokens.ink,
                              fontFamily: tokens.fontFamily,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _addProvider,
                          child: const Text('添加'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: providers.isEmpty
                        ? FluentProvidersListEmpty(
                            onAdd: _addProvider,
                            illustration:
                                const FluentEmptyIllustration.noProviders(),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                            itemCount: providers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final p = providers[index];
                              final active = p.id == _selectedId;
                              return _ProviderListTile(
                                provider: p,
                                selected: active,
                                onPressed: () => _selectProvider(p.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      '选择或添加一个提供商',
                      style: TextStyle(
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  )
                : _ProviderForm(
                    tokens: tokens,
                    nameCtrl: _nameCtrl,
                    baseUrlCtrl: _baseUrlCtrl,
                    apiKeyCtrl: _apiKeyCtrl,
                    chatModelCtrl: _chatModelCtrl,
                    imageModelCtrl: _imageModelCtrl,
                    videoModelCtrl: _videoModelCtrl,
                    type: _type,
                    obscureKey: _obscureKey,
                    testing: _testing,
                    listingModels: _listingModels,
                    canProbe: _canProbeConnection,
                    statusText: _statusText,
                    statusOk: _statusOk,
                    dirty: _dirty,
                    canDelete: !selected.builtin,
                    chatModelOptions: _stableOptions(
                      ModelKind.chat,
                      _dirty
                          ? _chatModelCtrl.text
                          : (_selected?.chatModel ?? ''),
                    ),
                    imageModelOptions: _stableOptions(
                      ModelKind.image,
                      _dirty
                          ? _imageModelCtrl.text
                          : (_selected?.imageModel ?? ''),
                    ),
                    videoModelOptions: _stableOptions(
                      ModelKind.video,
                      _dirty
                          ? _videoModelCtrl.text
                          : (_selected?.videoModel ?? ''),
                    ),
                    onTypeChanged: (t) {
                      setState(() {
                        _type = t;
                        _chatModelCtrl.clear();
                        _imageModelCtrl.clear();
                        _videoModelCtrl.clear();
                        _modelHints = const [];
                        _dirty = true;
                      });
                    },
                    onToggleObscure: () =>
                        setState(() => _obscureKey = !_obscureKey),
                    onFieldChanged: (_) => _markDirty(),
                    onSave: _save,
                    onCancel: _cancelEdits,
                    onDelete: _delete,
                    onTest: _testConnection,
                    onPullModels: _pullModels,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.onPressed,
  });

  final ProviderConfig provider;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final border = selected
        ? Color.lerp(tokens.primary, tokens.border, 0.5)!
        : tokens.border;
    final bg = tokens.surface;

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

    return Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        backgroundColor: WidgetStatePropertyAll(bg),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: border),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFamily: tokens.fontFamily,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Color.lerp(pillFg, tokens.border, 0.55)!,
                  ),
                ),
                child: Text(
                  pill,
                  style: TextStyle(
                    fontSize: 10,
                    color: pillFg,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ProviderForm extends StatelessWidget {
  const _ProviderForm({
    required this.tokens,
    required this.nameCtrl,
    required this.baseUrlCtrl,
    required this.apiKeyCtrl,
    required this.chatModelCtrl,
    required this.imageModelCtrl,
    required this.videoModelCtrl,
    required this.type,
    required this.obscureKey,
    required this.testing,
    required this.listingModels,
    required this.canProbe,
    required this.statusText,
    required this.statusOk,
    required this.dirty,
    required this.canDelete,
    required this.chatModelOptions,
    required this.imageModelOptions,
    required this.videoModelOptions,
    required this.onTypeChanged,
    required this.onToggleObscure,
    required this.onFieldChanged,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
    required this.onTest,
    required this.onPullModels,
  });

  final FluentTokens tokens;
  final TextEditingController nameCtrl;
  final TextEditingController baseUrlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController chatModelCtrl;
  final TextEditingController imageModelCtrl;
  final TextEditingController videoModelCtrl;
  final ProviderType type;
  final bool obscureKey;
  final bool testing;
  final bool listingModels;
  final bool canProbe;
  final String? statusText;
  final bool statusOk;
  final bool dirty;
  final bool canDelete;
  final List<ModelSelectOption> chatModelOptions;
  final List<ModelSelectOption> imageModelOptions;
  final List<ModelSelectOption> videoModelOptions;
  final ValueChanged<ProviderType> onTypeChanged;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onFieldChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final VoidCallback onPullModels;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tokens.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        children: [
          Text(
            '编辑提供商',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '元数据存本机；密钥存 OS 凭据库（不上传）；完整 Key 不写入日志。',
            style: TextStyle(
              fontSize: 13,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 20),
          _Section(
            title: '基本信息',
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: '显示名称',
                        child: TextBox(
                          controller: nameCtrl,
                          placeholder: '例如 OpenAI 兼容 · 自建',
                          onChanged: onFieldChanged,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '类型',
                        child: ComboBox<ProviderType>(
                          value: type,
                          isExpanded: true,
                          items: [
                            for (final t in ProviderType.values)
                              ComboBoxItem(value: t, child: Text(t.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) onTypeChanged(v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: 'Base URL',
                  child: TextBox(
                    controller: baseUrlCtrl,
                    placeholder: 'https://api.example.com/v1',
                    onChanged: onFieldChanged,
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: 'API Key',
                  child: TextBox(
                    controller: apiKeyCtrl,
                    obscureText: obscureKey,
                    placeholder: 'sk-…',
                    onChanged: onFieldChanged,
                    suffix: IconButton(
                      icon: Icon(
                        obscureKey ? FluentIcons.view : FluentIcons.hide3,
                        size: 14,
                      ),
                      onPressed: onToggleObscure,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: '连接与模型',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Button(
                      onPressed: (!canProbe || testing) ? null : onTest,
                      child: Text(testing ? '测试中…' : '测试连接'),
                    ),
                    FilledButton(
                      onPressed:
                          (!canProbe || listingModels) ? null : onPullModels,
                      child: Text(listingModels ? '拉取中…' : '拉取模型'),
                    ),
                    if (!canProbe)
                      Text(
                        '需先填写 Base URL 与 API Key',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      )
                    else if (statusText != null)
                      Text(
                        '● $statusText',
                        style: TextStyle(
                          fontSize: 12,
                          color: statusOk ? tokens.success : tokens.danger,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: '对话模型',
                  hint: '用于对话 /chat/completions（含流式）',
                  child: FilterableModelPicker(
                    controller: chatModelCtrl,
                    options: chatModelOptions,
                    placeholder: 'gpt-4o / grok-4.5',
                    onChanged: onFieldChanged,
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '生图模型',
                  hint: '文生图 / 图生图；可留空',
                  child: FilterableModelPicker(
                    controller: imageModelCtrl,
                    options: imageModelOptions,
                    placeholder: 'gpt-image-1 / grok-imagine-image',
                    onChanged: onFieldChanged,
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '视频模型',
                  hint: '文生视频 / 图生视频；可留空表示不支持',
                  child: FilterableModelPicker(
                    controller: videoModelCtrl,
                    options: videoModelOptions,
                    placeholder: 'sora-2 / grok-imagine-video',
                    onChanged: onFieldChanged,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '先「拉取模型」；列表可搜索筛选，也可直接输入自定义模型名。',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: dirty ? onSave : null,
                child: const Text('保存'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: dirty ? onCancel : null,
                child: const Text('取消'),
              ),
            ],
          ),
          if (canDelete) ...[
            const SizedBox(height: 18),
            HyperlinkButton(
              onPressed: onDelete,
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(tokens.danger),
              ),
              child: const Text('删除此提供商…'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.hint,
  });

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ],
    );
  }
}


