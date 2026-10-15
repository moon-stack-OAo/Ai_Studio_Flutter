import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/back_to_top_host.dart';

class SettingsChatDefaultsTab extends StatefulWidget {
  const SettingsChatDefaultsTab({super.key, required this.repository});

  final ChatDefaultsRepository repository;

  @override
  State<SettingsChatDefaultsTab> createState() =>
      _SettingsChatDefaultsTabState();
}

class _SettingsChatDefaultsTabState extends State<SettingsChatDefaultsTab>
    with AutomaticKeepAliveClientMixin {
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
  Map<TextEditingController, String> _errors = {};
  late ChatDefaults _baseline;
  bool get _hasConflict => _baseline != _repo.defaults;

  ChatDefaultsRepository get _repo => widget.repository;

  // TabBarView 回收失焦的子页时也要保留尚未保存的草稿。
  @override
  bool get wantKeepAlive => true;

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

  void _markDirty([TextEditingController? controller]) {
    if (_syncing || _saving) return;
    setState(() {
      _dirty = true;
      _errors.remove(controller);
    });
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

  ChatDefaults? _buildFromForm() {
    final errors = <TextEditingController, String>{};
    int? readInt(TextEditingController controller, int min, int max) {
      final text = controller.text.trim();
      final value = RegExp(r'^[0-9]+$').hasMatch(text)
          ? int.tryParse(text)
          : null;
      if (value == null || value < min || value > max) {
        errors[controller] = '请输入 $min～$max 之间的整数';
        return null;
      }
      return value;
    }

    final maxTokens = readInt(_maxTokensCtrl, 0, 200000);
    final timeoutSec = readInt(_timeoutSecCtrl, 1, 600);
    // 关闭的裁剪项不校验、不采用草稿，保留仓库里已保存的数值。
    final maxTurns = _trimEnabled
        ? readInt(_maxTurnsCtrl, 1, 200)
        : _repo.defaults.contextMaxTurns;
    final maxChars = _maxCharsEnabled
        ? readInt(_maxCharsCtrl, 1, 500000)
        : _repo.defaults.contextMaxChars;
    setState(() => _errors = errors);
    if (maxTokens == null ||
        timeoutSec == null ||
        maxTurns == null ||
        maxChars == null) {
      return null;
    }
    return ChatDefaults(
      temperature: _temperature,
      systemPrompt: _systemCtrl.text,
      maxTokens: maxTokens,
      apiTimeoutMs: timeoutSec * 1000,
      contextTrimEnabled: _trimEnabled,
      contextMaxTurns: maxTurns,
      contextMaxCharsEnabled: _maxCharsEnabled,
      contextMaxChars: maxChars,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final next = _buildFromForm();
    if (next == null) return;
    setState(() => _saving = true);
    try {
      if (_hasConflict &&
          !await showMaterialConfirmDialog(
            context: context,
            title: '覆盖最新配置？',
            message: '对话默认已被导入或其他操作更新。继续保存将用当前草稿覆盖最新配置。',
            confirmLabel: '覆盖保存',
            cancelLabel: '继续编辑',
          )) {
        return;
      }
      if (!mounted) return;
      // 确认框打开期间也可能导入配置，关闭的裁剪项沿用此刻已保存值。
      await _repo.save(
        next.copyWith(
          contextMaxTurns: _trimEnabled ? null : _repo.defaults.contextMaxTurns,
          contextMaxChars: _maxCharsEnabled
              ? null
              : _repo.defaults.contextMaxChars,
        ),
      );
      if (!mounted) return;
      _loadFromRepo();
      _snack('已保存对话默认');
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _onRepoChanged();
      }
    }
  }

  Future<void> _reset() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await showMaterialConfirmDialog(
        context: context,
        title: '恢复推荐值？',
        message: '将温度、超时、裁剪等恢复为推荐默认，当前未保存更改也会丢弃。',
        confirmLabel: '恢复',
      );
      if (!mounted || !ok) return;
      await _repo.resetToRecommended();
      if (!mounted) return;
      _loadFromRepo();
      _snack('已恢复推荐值');
    } catch (e) {
      if (!mounted) return;
      _snack('恢复失败：$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _onRepoChanged();
      }
    }
  }

  void _cancelEdits() {
    if (_saving) return;
    _loadFromRepo();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = materialTokensOf(context);

    return BackToTopHost(
      builder: (context, scroll) => ListView(
        controller: scroll,
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
                    '全局默认参数。单会话覆盖优先于本页；启用的对话技能会追加到最终系统提示。',
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 14),
                  if (_hasConflict)
                    const Text('本机配置已更新，当前草稿已保留。保存时需要确认覆盖；取消可载入最新配置。'),
                  TextField(
                    controller: _systemCtrl,
                    enabled: !_saving,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '系统提示',
                      hintText: '你是有用的本地助手。',
                      helperText: '留空不追加全局系统提示；已启用的对话技能仍会生效',
                      helperMaxLines: 3,
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
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (_saving) return;
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
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Max Tokens',
                      helperText: '0 = 不传 max_tokens',
                      errorText: _errors[_maxTokensCtrl],
                    ),
                    onChanged: (_) => _markDirty(_maxTokensCtrl),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timeoutSecCtrl,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '超时（秒）',
                      helperText: '默认 180 秒',
                      errorText: _errors[_timeoutSecCtrl],
                    ),
                    onChanged: (_) => _markDirty(_timeoutSecCtrl),
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
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (_saving) return;
                            setState(() {
                              _trimEnabled = v;
                              _dirty = true;
                              if (!v) _errors.remove(_maxTurnsCtrl);
                            });
                          },
                  ),
                  TextField(
                    controller: _maxTurnsCtrl,
                    enabled: _trimEnabled && !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '最大轮数',
                      helperText: '以 user 消息条数为轮；推荐 20',
                      errorText: _errors[_maxTurnsCtrl],
                    ),
                    onChanged: (_) => _markDirty(_maxTurnsCtrl),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用字符预算'),
                    value: _maxCharsEnabled,
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (_saving) return;
                            setState(() {
                              _maxCharsEnabled = v;
                              _dirty = true;
                              if (!v) _errors.remove(_maxCharsCtrl);
                            });
                          },
                  ),
                  TextField(
                    controller: _maxCharsCtrl,
                    enabled: _maxCharsEnabled && !_saving,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '最大字符数',
                      helperText: '粗估字符（非 Token）；推荐 32000',
                      errorText: _errors[_maxCharsCtrl],
                    ),
                    onChanged: (_) => _markDirty(_maxCharsCtrl),
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
      ),
    );
  }
}
