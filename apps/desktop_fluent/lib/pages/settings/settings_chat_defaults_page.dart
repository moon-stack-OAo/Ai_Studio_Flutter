import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/back_to_top_host.dart';
import 'widgets/settings_typography.dart';
import 'widgets/settings_conflict_notice.dart';

class SettingsChatDefaultsPage extends StatefulWidget {
  const SettingsChatDefaultsPage({super.key, required this.repository});

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
  final Map<String, String> _errors = {};
  late ChatDefaults _baseline;
  bool get _hasConflict => _baseline != _repo.defaults;

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
    if (!mounted || _saving) return;
    if (_dirty) {
      setState(() {});
    } else {
      _loadFromRepo();
    }
  }

  void _loadFromRepo() {
    final d = _repo.defaults;
    _baseline = d;
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
    _errors.clear();
    _syncing = false;
    if (mounted) setState(() {});
  }

  void _markDirty([String? field]) {
    if (_syncing || _saving) return;
    setState(() {
      _dirty = true;
      _errors.remove(field);
    });
  }

  bool _validateForm() {
    final errors = <String, String>{};
    void validate(String field, String text, int min, int max) {
      final input = text.trim();
      final value = RegExp(r'^[0-9]+$').hasMatch(input)
          ? int.tryParse(input)
          : null;
      if (value == null || value < min || value > max) {
        errors[field] = '请输入 $min～$max 的整数';
      }
    }

    validate('maxTokens', _maxTokensCtrl.text, 0, 200000);
    validate('timeoutSec', _timeoutSecCtrl.text, 1, 600);
    if (_trimEnabled) validate('maxTurns', _maxTurnsCtrl.text, 1, 200);
    if (_maxCharsEnabled) validate('maxChars', _maxCharsCtrl.text, 1, 500000);
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.isEmpty;
  }

  ChatDefaults _buildFromForm() {
    // 启用项已通过显式校验；关闭项保留最新已保存值，不提交禁用的草稿。
    final saved = _repo.defaults;
    return ChatDefaults(
      temperature: _temperature,
      systemPrompt: _systemCtrl.text,
      maxTokens: int.parse(_maxTokensCtrl.text.trim()),
      apiTimeoutMs: int.parse(_timeoutSecCtrl.text.trim()) * 1000,
      contextTrimEnabled: _trimEnabled,
      contextMaxTurns: _trimEnabled
          ? int.parse(_maxTurnsCtrl.text.trim())
          : saved.contextMaxTurns,
      contextMaxCharsEnabled: _maxCharsEnabled,
      contextMaxChars: _maxCharsEnabled
          ? int.parse(_maxCharsCtrl.text.trim())
          : saved.contextMaxChars,
    );
  }

  Future<void> _save() async {
    if (_saving || !_validateForm()) return;
    setState(() => _saving = true);
    try {
      if (_hasConflict) {
        final ok = await confirmSettingsOverwrite(context);
        if (!mounted || !ok) return;
      }
      await _repo.save(_buildFromForm());
      if (!mounted) return;
      _loadFromRepo();
      _showInfoBar('已保存对话默认', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('保存失败：$e', InfoBarSeverity.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await showFluentConfirmDialog(
        context: context,
        title: '恢复推荐值？',
        message: '将温度、超时、裁剪等恢复为推荐默认，当前未保存更改也会丢弃。',
        confirmLabel: '恢复',
      );
      if (!mounted || !ok) return;
      await _repo.resetToRecommended();
      if (!mounted) return;
      _loadFromRepo();
      _showInfoBar('已恢复推荐值', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('恢复失败：$e', InfoBarSeverity.error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (!_dirty) _loadFromRepo();
      }
    }
  }

  void _cancelEdits() {
    if (_saving) return;
    _loadFromRepo();
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
    return SettingsTypography(
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BackToTopHost(
              builder: (context, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
                children: [
                  Text('对话默认', style: context.settingsText.pageTitle),
                  const SizedBox(height: 6),
                  Text(
                    '全局默认参数。单会话覆盖优先于本页；启用的对话技能会追加到最终系统提示。',
                    style: context.settingsText.caption,
                  ),
                  const SizedBox(height: 18),
                  if (_hasConflict)
                    const InfoBar(
                      title: Text(settingsConflictMessage),
                      severity: InfoBarSeverity.warning,
                    ),
                  _Section(
                    title: '生成参数',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LabeledField(
                          label: '系统提示',
                          hint: '留空不追加全局系统提示；已启用的对话技能仍会生效',
                          child: TextBox(
                            controller: _systemCtrl,
                            enabled: !_saving,
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
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (_saving) return;
                                    setState(() {
                                      _temperature = double.parse(
                                        v.toStringAsFixed(2),
                                      );
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
                                error: _errors['maxTokens'],
                                child: TextBox(
                                  controller: _maxTokensCtrl,
                                  enabled: !_saving,
                                  placeholder: '0',
                                  onChanged: (_) => _markDirty('maxTokens'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _LabeledField(
                                label: '超时（秒）',
                                hint: '默认 180 秒',
                                error: _errors['timeoutSec'],
                                child: TextBox(
                                  controller: _timeoutSecCtrl,
                                  enabled: !_saving,
                                  placeholder: '180',
                                  onChanged: (_) => _markDirty('timeoutSec'),
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
                          onChanged: _saving
                              ? null
                              : (v) {
                                  if (_saving) return;
                                  setState(() {
                                    _trimEnabled = v;
                                    _errors.remove('maxTurns');
                                    _dirty = true;
                                  });
                                },
                          content: Text(
                            '按轮数裁剪上下文',
                            style: context.settingsText.body,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LabeledField(
                          label: '最大轮数',
                          hint: '以 user 消息条数为轮；推荐 20；关闭时保留已保存值',
                          error: _errors['maxTurns'],
                          child: TextBox(
                            controller: _maxTurnsCtrl,
                            placeholder: '20',
                            enabled: _trimEnabled && !_saving,
                            onChanged: (_) => _markDirty('maxTurns'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ToggleSwitch(
                          checked: _maxCharsEnabled,
                          onChanged: _saving
                              ? null
                              : (v) {
                                  if (_saving) return;
                                  setState(() {
                                    _maxCharsEnabled = v;
                                    _errors.remove('maxChars');
                                    _dirty = true;
                                  });
                                },
                          content: Text(
                            '启用字符预算',
                            style: context.settingsText.body,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _LabeledField(
                          label: '最大字符数',
                          hint: '粗估字符（非 Token）；推荐 32000；关闭时保留已保存值',
                          error: _errors['maxChars'],
                          child: TextBox(
                            controller: _maxCharsCtrl,
                            placeholder: '32000',
                            enabled: _maxCharsEnabled && !_saving,
                            onChanged: (_) => _markDirty('maxChars'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: Row(
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
                const Spacer(),
                Button(
                  onPressed: _saving ? null : _reset,
                  child: const Text('恢复推荐值'),
                ),
              ],
            ),
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
          Text(title, style: context.settingsText.sectionTitle),
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
    this.error,
  });

  final String label;
  final Widget child;
  final String? hint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.settingsText.label),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: context.settingsText.caption.copyWith(
              color: fluentTokensOf(context).danger,
            ),
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: context.settingsText.caption),
        ],
      ],
    );
  }
}
