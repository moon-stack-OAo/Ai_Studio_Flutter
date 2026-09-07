import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SettingsChatDefaultsPage extends StatefulWidget {
  const SettingsChatDefaultsPage({
    super.key,
    required this.repository,
  });

  final ChatDefaultsRepository repository;

  @override
  State<SettingsChatDefaultsPage> createState() =>
      _SettingsChatDefaultsPageState();
}

class _SettingsChatDefaultsPageState extends State<SettingsChatDefaultsPage> {
  late final TextEditingController _systemCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _timeoutSecCtrl;
  late final TextEditingController _maxTurnsCtrl;
  late final TextEditingController _maxCharsCtrl;

  double _temperature = defaultChatTemperature;
  bool _trimEnabled = true;
  bool _maxCharsEnabled = false;
  bool _dirty = false;
  bool _syncing = false;
  bool _saving = false;

  ChatDefaultsRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _systemCtrl = TextEditingController();
    _maxTokensCtrl = TextEditingController();
    _timeoutSecCtrl = TextEditingController();
    _maxTurnsCtrl = TextEditingController();
    _maxCharsCtrl = TextEditingController();
    _repo.addListener(_onRepoChanged);
    _loadFromRepo();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _systemCtrl.dispose();
    _maxTokensCtrl.dispose();
    _timeoutSecCtrl.dispose();
    _maxTurnsCtrl.dispose();
    _maxCharsCtrl.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (!mounted || _dirty) return;
    _loadFromRepo();
  }

  void _loadFromRepo() {
    final d = _repo.defaults;
    _syncing = true;
    _temperature = d.temperature;
    _trimEnabled = d.contextTrimEnabled;
    _maxCharsEnabled = d.contextMaxCharsEnabled;
    _systemCtrl.text = d.systemPrompt;
    _maxTokensCtrl.text = d.maxTokens.toString();
    _timeoutSecCtrl.text = (d.apiTimeoutMs / 1000).round().toString();
    _maxTurnsCtrl.text = d.contextMaxTurns.toString();
    _maxCharsCtrl.text = d.contextMaxChars.toString();
    _dirty = false;
    _syncing = false;
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (_syncing || _dirty) return;
    setState(() => _dirty = true);
  }

  ChatDefaults _buildFromForm() {
    final maxTokens = int.tryParse(_maxTokensCtrl.text.trim()) ?? 0;
    final timeoutSec = int.tryParse(_timeoutSecCtrl.text.trim()) ?? 180;
    final maxTurns =
        int.tryParse(_maxTurnsCtrl.text.trim()) ?? defaultChatContextMaxTurns;
    final maxChars =
        int.tryParse(_maxCharsCtrl.text.trim()) ?? defaultChatContextMaxChars;
    return ChatDefaults(
      temperature: _temperature,
      systemPrompt: _systemCtrl.text,
      maxTokens: maxTokens,
      apiTimeoutMs: timeoutSec * 1000,
      contextTrimEnabled: _trimEnabled,
      contextMaxTurns: maxTurns,
      contextMaxCharsEnabled: _maxCharsEnabled,
      contextMaxChars: maxChars,
    ).sanitized();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _repo.save(_buildFromForm());
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      _loadFromRepo();
      _showInfoBar('已保存对话默认', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showInfoBar('保存失败：$e', InfoBarSeverity.error);
    }
  }

  Future<void> _reset() async {
    final ok = await showFluentConfirmDialog(
      context: context,
      title: '恢复推荐值？',
      message: '将温度、超时、裁剪等恢复为推荐默认，当前未保存更改也会丢弃。',
      confirmLabel: '恢复',
    );
    if (!ok) return;
    setState(() => _saving = true);
    try {
      await _repo.resetToRecommended();
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      _loadFromRepo();
      _showInfoBar('已恢复推荐值', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showInfoBar('恢复失败：$e', InfoBarSeverity.error);
    }
  }

  void _cancelEdits() => _loadFromRepo();

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
    return ColoredBox(
      color: tokens.canvas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        children: [
          Text(
            '对话默认',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '全局默认参数。单会话覆盖优先于本页；空系统提示不传 system。',
            style: TextStyle(
              fontSize: 13,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 18),
          _Section(
            title: '生成参数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LabeledField(
                  label: '系统提示',
                  hint: '留空则不向 API 传 system 消息',
                  child: TextBox(
                    controller: _systemCtrl,
                    maxLines: 5,
                    placeholder: '你是有用的本地助手。',
                    onChanged: (_) => _markDirty(),
                  ),
                ),
                const SizedBox(height: 14),
                _LabeledField(
                  label: '温度 ${_temperature.toStringAsFixed(2)}',
                  hint: '0 = 更确定 · 2 = 更随机',
                  child: Slider(
                    value: _temperature,
                    min: 0,
                    max: 2,
                    divisions: 40,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (v) {
                      setState(() {
                        _temperature = double.parse(v.toStringAsFixed(2));
                        _dirty = true;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'Max Tokens',
                        hint: '0 = 不传 max_tokens',
                        child: TextBox(
                          controller: _maxTokensCtrl,
                          placeholder: '0',
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: '超时（秒）',
                        hint: '默认 180 秒',
                        child: TextBox(
                          controller: _timeoutSecCtrl,
                          placeholder: '180',
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Section(
            title: '上下文裁剪',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ToggleSwitch(
                  checked: _trimEnabled,
                  onChanged: (v) {
                    setState(() {
                      _trimEnabled = v;
                      _dirty = true;
                    });
                  },
                  content: Text(
                    '按轮数裁剪上下文',
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.ink,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '最大轮数',
                  hint: '以 user 消息条数为轮；推荐 20',
                  child: TextBox(
                    controller: _maxTurnsCtrl,
                    placeholder: '20',
                    enabled: _trimEnabled,
                    onChanged: (_) => _markDirty(),
                  ),
                ),
                const SizedBox(height: 14),
                ToggleSwitch(
                  checked: _maxCharsEnabled,
                  onChanged: (v) {
                    setState(() {
                      _maxCharsEnabled = v;
                      _dirty = true;
                    });
                  },
                  content: Text(
                    '启用字符预算',
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.ink,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '最大字符数',
                  hint: '粗估字符（非 Token）；推荐 32000',
                  child: TextBox(
                    controller: _maxCharsCtrl,
                    placeholder: '32000',
                    enabled: _maxCharsEnabled,
                    onChanged: (_) => _markDirty(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: (_dirty && !_saving) ? _save : null,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: (_dirty && !_saving) ? _cancelEdits : null,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              Button(
                onPressed: _saving ? null : _reset,
                child: const Text('恢复推荐值'),
              ),
            ],
          ),
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
