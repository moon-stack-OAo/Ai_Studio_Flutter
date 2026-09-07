import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsChatDefaultsTab extends StatefulWidget {
  const SettingsChatDefaultsTab({
    super.key,
    required this.repository,
  });

  final ChatDefaultsRepository repository;

  @override
  State<SettingsChatDefaultsTab> createState() =>
      _SettingsChatDefaultsTabState();
}

class _SettingsChatDefaultsTabState extends State<SettingsChatDefaultsTab> {
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
      _snack('已保存对话默认');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('保存失败：$e', error: true);
    }
  }

  Future<void> _reset() async {
    final ok = await showMaterialConfirmDialog(
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
      _snack('已恢复推荐值');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('恢复失败：$e', error: true);
    }
  }

  void _cancelEdits() => _loadFromRepo();

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '对话默认',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '全局默认参数。单会话覆盖优先于本页；空系统提示不传 system。',
                  style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _systemCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '系统提示',
                    hintText: '你是有用的本地助手。',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),
                Text(
                  '温度 ${_temperature.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkSecondary,
                  ),
                ),
                Slider(
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
                Text(
                  '0 = 更确定 · 2 = 更随机',
                  style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _maxTokensCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Max Tokens',
                    helperText: '0 = 不传 max_tokens',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _timeoutSecCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '超时（秒）',
                    helperText: '默认 180 秒',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '上下文裁剪',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('按轮数裁剪上下文'),
                  value: _trimEnabled,
                  onChanged: (v) {
                    setState(() {
                      _trimEnabled = v;
                      _dirty = true;
                    });
                  },
                ),
                TextField(
                  controller: _maxTurnsCtrl,
                  enabled: _trimEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '最大轮数',
                    helperText: '以 user 消息条数为轮；推荐 20',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用字符预算'),
                  value: _maxCharsEnabled,
                  onChanged: (v) {
                    setState(() {
                      _maxCharsEnabled = v;
                      _dirty = true;
                    });
                  },
                ),
                TextField(
                  controller: _maxCharsCtrl,
                  enabled: _maxCharsEnabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '最大字符数',
                    helperText: '粗估字符（非 Token）；推荐 32000',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: (_dirty && !_saving) ? _save : null,
              child: Text(_saving ? '保存中…' : '保存默认'),
            ),
            OutlinedButton(
              onPressed: (_dirty && !_saving) ? _cancelEdits : null,
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: _saving ? null : _reset,
              child: const Text('恢复推荐值'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '本会话覆盖在对话页顶栏「会话参数」中设置，不写入此处。',
          style: TextStyle(fontSize: 11, color: tokens.inkMuted),
        ),
      ],
    );
  }
}
