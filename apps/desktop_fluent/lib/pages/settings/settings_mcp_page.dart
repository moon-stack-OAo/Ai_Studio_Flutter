import 'dart:async';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../widgets/back_to_top_host.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/fluent_empty_states.dart';

/// SET-MCP / SET-MCP-EDIT / SET-MCP-POLICY：业务 MCP Server 配置（含桌面 stdio）。
class SettingsMcpPage extends StatefulWidget {
  const SettingsMcpPage({
    super.key,
    required this.repository,
    required this.sessionFactory,
  });

  final McpServerRepository repository;
  final McpSessionFactory sessionFactory;

  @override
  State<SettingsMcpPage> createState() => _SettingsMcpPageState();
}

class _SettingsMcpPageState extends State<SettingsMcpPage> {
  String? _selectedId;
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _commandCtrl = TextEditingController();
  final _argsCtrl = TextEditingController();
  final _cwdCtrl = TextEditingController();
  final _envCtrl = TextEditingController();
  McpTransport _transport = McpTransport.http;
  McpAuthKind _authKind = McpAuthKind.none;
  bool _enabled = true;
  bool _obscureToken = true;
  bool _hasStoredToken = false;
  bool _probing = false;
  String? _statusText;
  bool _statusOk = false;
  bool _dirty = false;
  bool _syncingForm = false;
  String? _confirmedStdioSummary;

  McpServerRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _baseUrlCtrl.addListener(_onFieldsChanged);
    _nameCtrl.addListener(_onFieldsChanged);
    _tokenCtrl.addListener(_onFieldsChanged);
    _commandCtrl.addListener(_onFieldsChanged);
    _argsCtrl.addListener(_onFieldsChanged);
    _cwdCtrl.addListener(_onFieldsChanged);
    _envCtrl.addListener(_onFieldsChanged);
    if (_repo.servers.isNotEmpty) {
      _selectedId = _repo.servers.first.id;
    }
    _loadFormFromSelected();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _baseUrlCtrl.removeListener(_onFieldsChanged);
    _nameCtrl.removeListener(_onFieldsChanged);
    _tokenCtrl.removeListener(_onFieldsChanged);
    _commandCtrl.removeListener(_onFieldsChanged);
    _argsCtrl.removeListener(_onFieldsChanged);
    _cwdCtrl.removeListener(_onFieldsChanged);
    _envCtrl.removeListener(_onFieldsChanged);
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    _commandCtrl.dispose();
    _argsCtrl.dispose();
    _cwdCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    if (!mounted || _syncingForm) return;
    _markDirty();
    setState(() {});
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final exists = _repo.servers.any((s) => s.id == _selectedId);
    if (!exists) {
      _selectedId =
          _repo.servers.isEmpty ? null : _repo.servers.first.id;
      _loadFormFromSelected();
    }
    setState(() {});
  }

  McpServerConfig? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    return _repo.findById(id);
  }

  static List<String> _parseArgsLines(String raw) {
    final out = <String>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  static Map<String, String> _parseEnvLines(String raw) {
    final out = <String, String>{};
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final eq = t.indexOf('=');
      if (eq <= 0) continue;
      final key = t.substring(0, eq).trim();
      if (key.isEmpty) continue;
      out[key] = t.substring(eq + 1);
    }
    return out;
  }

  static String _formatArgs(List<String> args) => args.join('\n');

  static String _formatEnv(Map<String, String> env) {
    if (env.isEmpty) return '';
    final keys = env.keys.toList()..sort();
    return keys.map((k) => '$k=${env[k]}').join('\n');
  }

  String _stdioCommandSummary({
    String? command,
    List<String>? args,
  }) {
    final cmd = (command ?? _commandCtrl.text).trim();
    final a = args ?? _parseArgsLines(_argsCtrl.text);
    if (cmd.isEmpty) return '';
    if (a.isEmpty) return cmd;
    return '$cmd ${a.join(' ')}';
  }

  Future<void> _loadFormFromSelected() async {
    final s = _selected;
    _syncingForm = true;
    if (s == null) {
      _nameCtrl.clear();
      _baseUrlCtrl.clear();
      _tokenCtrl.clear();
      _commandCtrl.clear();
      _argsCtrl.clear();
      _cwdCtrl.clear();
      _envCtrl.clear();
      _transport = McpTransport.http;
      _authKind = McpAuthKind.none;
      _enabled = true;
      _hasStoredToken = false;
      _statusText = null;
      _dirty = false;
      _confirmedStdioSummary = null;
    } else {
      _nameCtrl.text = s.displayName;
      _baseUrlCtrl.text = s.baseUrl;
      _tokenCtrl.clear();
      _commandCtrl.text = s.command ?? '';
      _argsCtrl.text = _formatArgs(s.args);
      _cwdCtrl.text = s.cwd ?? '';
      _envCtrl.text = _formatEnv(s.env);
      _transport = s.transport;
      _authKind = s.authKind == McpAuthKind.oauth
          ? McpAuthKind.none
          : s.authKind;
      _enabled = s.enabled;
      _hasStoredToken = await _repo.hasBearerSecret(s.id);
      _confirmedStdioSummary = s.transport == McpTransport.stdio && s.hasCommand
          ? _stdioCommandSummary(command: s.command, args: s.args)
          : null;
      if (s.lastError != null && s.lastError!.isNotEmpty) {
        _statusText = s.lastError;
        _statusOk = s.probeStatus == McpProbeStatus.ready;
      } else if (s.probeStatus == McpProbeStatus.ready) {
        _statusText = '已就绪 · ${s.toolsCache.length} 个工具';
        _statusOk = true;
      } else {
        _statusText = null;
        _statusOk = false;
      }
      _dirty = false;
    }
    _syncingForm = false;
    if (mounted) setState(() {});
  }

  void _markDirty() {
    if (_syncingForm || _dirty) return;
    setState(() => _dirty = true);
  }

  Future<void> _selectServer(String id) async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    setState(() => _selectedId = id);
    await _loadFormFromSelected();
  }

  Future<bool?> _confirmDiscard() async {
    return showFluentConfirmDialog(
      context: context,
      title: '放弃未保存更改？',
      message: '当前表单有未保存修改，切换 Server 将丢失这些更改。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃',
    );
  }

  Future<bool> _confirmStdioLaunch() async {
    final summary = _stdioCommandSummary();
    if (summary.isEmpty) return false;
    if (_confirmedStdioSummary == summary) return true;
    final cwd = _cwdCtrl.text.trim();
    final envCount = _parseEnvLines(_envCtrl.text).length;
    final ok = await showFluentConfirmDialog(
      context: context,
      title: '确认启动本机进程？',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('将启动本机进程（仅桌面可用；移动端不支持本地 stdio）：'),
          const SizedBox(height: 10),
          SelectableText(
            summary,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
          ),
          if (cwd.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('工作目录：$cwd'),
          ],
          if (envCount > 0) ...[
            const SizedBox(height: 4),
            Text('额外环境变量：$envCount 项'),
          ],
          const SizedBox(height: 10),
          const Text('请确认命令来源可信。取消则不会保存或启动。'),
        ],
      ),
      cancelLabel: '取消',
      confirmLabel: '确认启动',
      isDestructive: true,
      constraints: const BoxConstraints(maxWidth: 480),
    );
    if (ok) {
      _confirmedStdioSummary = summary;
    }
    return ok;
  }

  Future<void> _addServer() async {
    if (_dirty) {
      final discard = await _confirmDiscard();
      if (discard != true) return;
    }
    final id = await _repo.add(
      displayName: '新 MCP Server',
      baseUrl: '',
      enabled: true,
    );
    setState(() => _selectedId = id);
    await _loadFormFromSelected();
    _showInfoBar('已添加 MCP Server', InfoBarSeverity.success);
  }

  Future<bool> _save() async {
    final current = _selected;
    if (current == null) return false;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showInfoBar('请填写显示名称', InfoBarSeverity.warning);
      return false;
    }

    if (_transport == McpTransport.stdio) {
      final command = _commandCtrl.text.trim();
      if (command.isEmpty) {
        _showInfoBar('本地 stdio 须填写可执行文件 command', InfoBarSeverity.warning);
        return false;
      }
      final confirmed = await _confirmStdioLaunch();
      if (!confirmed) return false;
    }

    final baseUrl = _baseUrlCtrl.text.trim();
    if (_transport == McpTransport.http && baseUrl.isNotEmpty) {
      try {
        assertSafeHttpUrl(Uri.parse(baseUrl));
      } on UrlSafetyException catch (e) {
        _showInfoBar(e.message, InfoBarSeverity.error);
        return false;
      } catch (_) {
        _showInfoBar('Base URL 无效', InfoBarSeverity.error);
        return false;
      }
    }
    final urlRisk =
        _transport == McpTransport.http ? warnUnsafeUrl(baseUrl) : null;

    final args = _parseArgsLines(_argsCtrl.text);
    final env = _parseEnvLines(_envCtrl.text);
    final cwdRaw = _cwdCtrl.text.trim();
    final commandRaw = _commandCtrl.text.trim();

    var next = current.copyWith(
      displayName: name,
      transport: _transport,
      baseUrl: _transport == McpTransport.http ? baseUrl : '',
      command: _transport == McpTransport.stdio ? commandRaw : null,
      clearCommand: _transport != McpTransport.stdio,
      args: _transport == McpTransport.stdio ? args : const [],
      env: _transport == McpTransport.stdio ? env : const {},
      cwd: _transport == McpTransport.stdio && cwdRaw.isNotEmpty
          ? cwdRaw
          : null,
      clearCwd: _transport != McpTransport.stdio || cwdRaw.isEmpty,
      enabled: _enabled,
      authKind: _transport == McpTransport.stdio
          ? McpAuthKind.none
          : _authKind,
    );

    if (_transport == McpTransport.stdio ||
        _authKind == McpAuthKind.none) {
      await _repo.clearBearerSecret(current.id);
      next = next.copyWith(
        authKind: McpAuthKind.none,
        clearAuthSecretRef: true,
      );
    } else if (_authKind == McpAuthKind.bearer) {
      final typed = _tokenCtrl.text.trim();
      if (typed.isNotEmpty) {
        await _repo.writeBearerSecret(current.id, typed);
        final refreshed = _repo.findById(current.id) ?? next;
        next = refreshed.copyWith(
          displayName: name,
          transport: _transport,
          baseUrl: baseUrl,
          enabled: _enabled,
          authKind: McpAuthKind.bearer,
        );
      } else if (!_hasStoredToken) {
        _showInfoBar('Bearer 鉴权请填写 Token', InfoBarSeverity.warning);
        return false;
      } else {
        next = next.copyWith(authKind: McpAuthKind.bearer);
      }
    }

    await _repo.update(next);
    _tokenCtrl.clear();
    await _loadFormFromSelected();
    _showInfoBar('已保存', InfoBarSeverity.success);
    if (urlRisk != null) {
      _showInfoBar(urlRisk, InfoBarSeverity.warning);
    }
    return true;
  }

  void _cancelEdits() {
    _loadFormFromSelected();
  }

  Future<void> _delete() async {
    final current = _selected;
    if (current == null) return;
    final ok = await showFluentConfirmDialog(
      context: context,
      title: '删除此 MCP Server？',
      message: '将删除「${current.displayName}」及其本机 Token，此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!ok) return;
    await _repo.delete(current.id);
    setState(() {
      _selectedId =
          _repo.servers.isEmpty ? null : _repo.servers.first.id;
    });
    await _loadFormFromSelected();
    _showInfoBar('已删除', InfoBarSeverity.success);
  }

  bool get _canProbe {
    if (_transport == McpTransport.stdio) {
      return _commandCtrl.text.trim().isNotEmpty;
    }
    return _baseUrlCtrl.text.trim().isNotEmpty;
  }

  Future<void> _probeAndRefreshTools() async {
    final current = _selected;
    if (current == null) return;
    if (!_canProbe) {
      _showInfoBar(
        _transport == McpTransport.stdio
            ? '请先填写 command'
            : '请先填写 Base URL',
        InfoBarSeverity.warning,
      );
      return;
    }
    if (_transport == McpTransport.stdio) {
      final confirmed = await _confirmStdioLaunch();
      if (!confirmed) return;
    }
    if (_dirty) {
      final saved = await _save();
      if (!saved) return;
    }
    final server = _repo.findById(current.id);
    if (server == null || !server.canExposeTools) {
      _showInfoBar(
        _transport == McpTransport.stdio
            ? '请先保存有效的 command'
            : '请先保存有效的 Base URL',
        InfoBarSeverity.warning,
      );
      return;
    }

    setState(() {
      _probing = true;
      _statusText = '探测中…';
      _statusOk = false;
    });
    await _repo.update(
      server.copyWith(
        probeStatus: McpProbeStatus.probing,
        clearLastError: true,
      ),
    );

    McpSession? session;
    try {
      session = widget.sessionFactory.create(server);
      final result = await session.probe();
      if (!mounted) return;
      if (result.ok) {
        final tools = result.tools ?? const <McpToolDescriptor>[];
        await _repo.replaceToolsCache(server.id, tools);
        await _repo.update(
          (_repo.findById(server.id) ?? server).copyWith(
            probeStatus: McpProbeStatus.ready,
            lastProbeAtMs: result.atMs,
            clearLastError: true,
            toolsCache: tools,
          ),
        );
        setState(() {
          _probing = false;
          _statusOk = true;
          _statusText =
              '连接成功${result.serverName != null ? ' · ${result.serverName}' : ''} · ${tools.length} 个工具';
        });
        _showInfoBar('已刷新 ${tools.length} 个工具', InfoBarSeverity.success);
      } else {
        final msg = result.errorMessage ?? '探测失败';
        await _repo.update(
          (_repo.findById(server.id) ?? server).copyWith(
            probeStatus: McpProbeStatus.error,
            lastError: msg,
            lastProbeAtMs: result.atMs,
          ),
        );
        setState(() {
          _probing = false;
          _statusOk = false;
          _statusText = msg;
        });
        _showInfoBar(msg, InfoBarSeverity.error);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = mcpSanitizeSummary(e.toString(), maxLen: 200);
      await _repo.update(
        (_repo.findById(server.id) ?? server).copyWith(
          probeStatus: McpProbeStatus.error,
          lastError: msg,
        ),
      );
      setState(() {
        _probing = false;
        _statusOk = false;
        _statusText = msg;
      });
      _showInfoBar('探测失败：$msg', InfoBarSeverity.error);
    } finally {
      try {
        session?.close();
      } catch (_) {}
    }
  }

  Future<void> _setToolPolicy(String toolName, McpToolPolicyLevel? level) async {
    final id = _selectedId;
    if (id == null) return;
    await _repo.setToolPolicyOverride(id, toolName, level);
  }

  Future<void> _setDefaultToolPolicy(McpToolPolicyLevel? level) async {
    final id = _selectedId;
    if (id == null) return;
    await _repo.setDefaultToolPolicy(id, level);
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
    final servers = _repo.servers;
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
                            '业务 MCP',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: tokens.ink,
                              fontFamily: tokens.fontFamily,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: _addServer,
                          child: const Text('添加 Server'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: servers.isEmpty
                        ? FluentContentEmpty(
                            hint: '尚未配置 MCP Server',
                            subtitle: '添加业务 MCP 后，对话模型可调用其 tools。',
                            illustration:
                                const FluentEmptyIllustration.noProviders(),
                            actionLabel: '添加 Server',
                            onAction: _addServer,
                          )
                        : BackToTopHost(
                            builder: (context, scroll) => ListView.separated(
                              controller: scroll,
                              padding:
                                  const EdgeInsets.fromLTRB(10, 0, 10, 16),
                              itemCount: servers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final s = servers[index];
                                return _McpListTile(
                                  server: s,
                                  selected: s.id == _selectedId,
                                  onPressed: () => _selectServer(s.id),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: selected == null
                ? FluentContentEmpty(
                    hint: '选择或添加一个 MCP Server',
                    subtitle: '左侧列表点选后编辑；也可点「添加 Server」。',
                    illustration: const FluentEmptyIllustration.noProviders(),
                  )
                : _McpForm(
                    tokens: tokens,
                    nameCtrl: _nameCtrl,
                    baseUrlCtrl: _baseUrlCtrl,
                    tokenCtrl: _tokenCtrl,
                    commandCtrl: _commandCtrl,
                    argsCtrl: _argsCtrl,
                    cwdCtrl: _cwdCtrl,
                    envCtrl: _envCtrl,
                    transport: _transport,
                    authKind: _authKind,
                    enabled: _enabled,
                    obscureToken: _obscureToken,
                    hasStoredToken: _hasStoredToken,
                    probing: _probing,
                    canProbe: _canProbe,
                    statusText: _statusText,
                    statusOk: _statusOk,
                    dirty: _dirty,
                    tools: selected.toolsCache,
                    defaultToolPolicy: selected.defaultToolPolicy,
                    policyOverrides: selected.toolPolicyOverrides,
                    onTransportChanged: (v) {
                      setState(() {
                        _transport = v;
                        _dirty = true;
                        _confirmedStdioSummary = null;
                        if (v == McpTransport.stdio) {
                          _authKind = McpAuthKind.none;
                          _tokenCtrl.clear();
                        }
                      });
                    },
                    onAuthKindChanged: (v) {
                      setState(() {
                        _authKind = v;
                        _dirty = true;
                        if (v != McpAuthKind.bearer) {
                          _tokenCtrl.clear();
                        }
                      });
                    },
                    onEnabledChanged: (v) {
                      setState(() {
                        _enabled = v;
                        _dirty = true;
                      });
                    },
                    onToggleObscure: () =>
                        setState(() => _obscureToken = !_obscureToken),
                    onFieldChanged: (_) => _markDirty(),
                    onSave: () {
                      unawaited(_save());
                    },
                    onCancel: _cancelEdits,
                    onDelete: _delete,
                    onProbe: _probeAndRefreshTools,
                    onDefaultPolicyChanged: _setDefaultToolPolicy,
                    onPolicyChanged: _setToolPolicy,
                  ),
          ),
        ],
      ),
    );
  }
}

class _McpListTile extends StatelessWidget {
  const _McpListTile({
    required this.server,
    required this.selected,
    required this.onPressed,
  });

  final McpServerConfig server;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final border = selected
        ? Color.lerp(tokens.primary, tokens.border, 0.5)!
        : tokens.border;
    final isStdio = server.transport == McpTransport.stdio;

    late final String pill;
    late final Color pillFg;
    late final Color pillBg;
    if (!server.enabled) {
      pill = '已停用';
      pillFg = tokens.inkMuted;
      pillBg = tokens.surfaceMuted;
    } else if (server.probeStatus == McpProbeStatus.ready) {
      pill = '已就绪';
      pillFg = tokens.success;
      pillBg = Color.lerp(tokens.success, tokens.surface, 0.88)!;
    } else if (server.probeStatus == McpProbeStatus.error) {
      pill = '失败';
      pillFg = tokens.danger;
      pillBg = Color.lerp(tokens.danger, tokens.surface, 0.9)!;
    } else if (!server.canExposeTools) {
      pill = '待配置';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    } else {
      pill = '待探测';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    }

    final meta = isStdio
        ? (server.hasCommand
            ? [
                server.command!.trim(),
                ...server.args,
              ].join(' ')
            : '未填写 command')
        : (server.baseUrl.trim().isNotEmpty
            ? server.baseUrl.trim()
            : '未填写 Base URL');

    return Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        backgroundColor: WidgetStatePropertyAll(tokens.surface),
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
                  server.displayName,
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
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.border),
                ),
                child: Text(
                  isStdio ? 'stdio' : 'HTTP',
                  style: TextStyle(
                    fontSize: 10,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
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

class _McpForm extends StatelessWidget {
  const _McpForm({
    required this.tokens,
    required this.nameCtrl,
    required this.baseUrlCtrl,
    required this.tokenCtrl,
    required this.commandCtrl,
    required this.argsCtrl,
    required this.cwdCtrl,
    required this.envCtrl,
    required this.transport,
    required this.authKind,
    required this.enabled,
    required this.obscureToken,
    required this.hasStoredToken,
    required this.probing,
    required this.canProbe,
    required this.statusText,
    required this.statusOk,
    required this.dirty,
    required this.tools,
    required this.defaultToolPolicy,
    required this.policyOverrides,
    required this.onTransportChanged,
    required this.onAuthKindChanged,
    required this.onEnabledChanged,
    required this.onToggleObscure,
    required this.onFieldChanged,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
    required this.onProbe,
    required this.onDefaultPolicyChanged,
    required this.onPolicyChanged,
  });

  final FluentTokens tokens;
  final TextEditingController nameCtrl;
  final TextEditingController baseUrlCtrl;
  final TextEditingController tokenCtrl;
  final TextEditingController commandCtrl;
  final TextEditingController argsCtrl;
  final TextEditingController cwdCtrl;
  final TextEditingController envCtrl;
  final McpTransport transport;
  final McpAuthKind authKind;
  final bool enabled;
  final bool obscureToken;
  final bool hasStoredToken;
  final bool probing;
  final bool canProbe;
  final String? statusText;
  final bool statusOk;
  final bool dirty;
  final List<McpToolDescriptor> tools;
  final McpToolPolicyLevel? defaultToolPolicy;
  final Map<String, McpToolPolicyLevel> policyOverrides;
  final ValueChanged<McpTransport> onTransportChanged;
  final ValueChanged<McpAuthKind> onAuthKindChanged;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onFieldChanged;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onProbe;
  final ValueChanged<McpToolPolicyLevel?> onDefaultPolicyChanged;
  final void Function(String toolName, McpToolPolicyLevel? level)
      onPolicyChanged;

  bool get _isStdio => transport == McpTransport.stdio;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tokens.surface,
      child: BackToTopHost(
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          children: [
            Text(
              '编辑 MCP Server',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isStdio
                  ? '本地 stdio 仅桌面可用；将启动本机子进程。移动端不支持。元数据存本机。'
                  : '元数据存本机；Bearer Token 存 OS 凭据库。HTTP/SSE（Streamable JSON-RPC）。',
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
                  _LabeledField(
                    label: '显示名称',
                    child: TextBox(
                      controller: nameCtrl,
                      placeholder: '例如 业务查询 MCP',
                      onChanged: onFieldChanged,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _LabeledField(
                    label: '传输方式',
                    hint: '移动端仅支持 HTTP/SSE；stdio 仅 Windows / macOS',
                    child: ComboBox<McpTransport>(
                      value: transport,
                      isExpanded: true,
                      items: const [
                        ComboBoxItem(
                          value: McpTransport.http,
                          child: Text('HTTP/SSE'),
                        ),
                        ComboBoxItem(
                          value: McpTransport.stdio,
                          child: Text('本地 stdio（仅桌面）'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) onTransportChanged(v);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isStdio) ...[
                    _LabeledField(
                      label: '可执行文件（command）',
                      hint: '如 node、npx 或绝对路径',
                      child: TextBox(
                        controller: commandCtrl,
                        placeholder: 'node',
                        onChanged: onFieldChanged,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: '参数（args）',
                      hint: '每行一个参数',
                      child: TextBox(
                        controller: argsCtrl,
                        maxLines: 4,
                        placeholder: 'path/to/server.js',
                        onChanged: onFieldChanged,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: '工作目录（cwd，可选）',
                      child: TextBox(
                        controller: cwdCtrl,
                        placeholder: '留空则用进程默认目录',
                        onChanged: onFieldChanged,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: '环境变量（env，可选）',
                      hint: '每行 KEY=VALUE；含密钥时勿依赖默认备份',
                      child: TextBox(
                        controller: envCtrl,
                        maxLines: 4,
                        placeholder: 'API_KEY=…',
                        onChanged: onFieldChanged,
                      ),
                    ),
                  ] else
                    _LabeledField(
                      label: 'Base URL',
                      hint: 'MCP 单一入口，如 https://host/mcp',
                      child: TextBox(
                        controller: baseUrlCtrl,
                        placeholder: 'https://mcp.example.com/mcp',
                        onChanged: onFieldChanged,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '启用',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkSecondary,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ToggleSwitch(
                        checked: enabled,
                        onChanged: onEnabledChanged,
                      ),
                      const Spacer(),
                      Text(
                        enabled ? '对话可暴露其 tools' : '已停用，不参与对话',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_isStdio) ...[
              const SizedBox(height: 14),
              _Section(
                title: '鉴权',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ComboBox<McpAuthKind>(
                      value: authKind == McpAuthKind.oauth
                          ? McpAuthKind.none
                          : authKind,
                      isExpanded: true,
                      items: const [
                        ComboBoxItem(
                          value: McpAuthKind.none,
                          child: Text('无鉴权'),
                        ),
                        ComboBoxItem(
                          value: McpAuthKind.bearer,
                          child: Text('Bearer Token'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) onAuthKindChanged(v);
                      },
                    ),
                    if (authKind == McpAuthKind.bearer) ...[
                      const SizedBox(height: 12),
                      _LabeledField(
                        label: 'Bearer Token',
                        hint: hasStoredToken && tokenCtrl.text.isEmpty
                            ? '已保存（留空保持不变）'
                            : null,
                        child: TextBox(
                          controller: tokenCtrl,
                          obscureText: obscureToken,
                          placeholder: hasStoredToken ? '••••••••' : 'token…',
                          onChanged: onFieldChanged,
                          suffix: IconButton(
                            icon: Icon(
                              obscureToken
                                  ? FluentIcons.view
                                  : FluentIcons.hide3,
                              size: 14,
                            ),
                            onPressed: onToggleObscure,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _Section(
              title: '连接与工具',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: (!canProbe || probing) ? null : onProbe,
                        child: Text(probing ? '探测中…' : '测试连接 / 刷新 tools'),
                      ),
                      if (!canProbe)
                        Text(
                          _isStdio ? '需先填写 command' : '需先填写 Base URL',
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
                  _ServerDefaultPolicyRow(
                    tokens: tokens,
                    value: defaultToolPolicy,
                    onChanged: onDefaultPolicyChanged,
                  ),
                  const SizedBox(height: 14),
                  if (tools.isEmpty)
                    Text(
                      _isStdio
                          ? '尚未拉取工具列表。保存 command 后点「测试连接 / 刷新 tools」。'
                          : '尚未拉取工具列表。保存 URL 后点「测试连接 / 刷新 tools」。',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    )
                  else
                    _ToolsPolicyTable(
                      tokens: tokens,
                      tools: tools,
                      defaultToolPolicy: defaultToolPolicy,
                      overrides: policyOverrides,
                      onPolicyChanged: onPolicyChanged,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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
                const Spacer(),
                Button(
                  onPressed: onDelete,
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(tokens.danger),
                  ),
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerDefaultPolicyRow extends StatelessWidget {
  const _ServerDefaultPolicyRow({
    required this.tokens,
    required this.value,
    required this.onChanged,
  });

  final FluentTokens tokens;
  final McpToolPolicyLevel? value;
  final ValueChanged<McpToolPolicyLevel?> onChanged;

  static String _levelShort(McpToolPolicyLevel level) => switch (level) {
        McpToolPolicyLevel.deny => '拒绝',
        McpToolPolicyLevel.confirmAlways => '每次确认',
        McpToolPolicyLevel.confirmOnce => '本会话确认一次',
        McpToolPolicyLevel.autoAllow => '自动允许',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '本 Server 默认授权',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '未单独覆盖的工具走此默认；读操作仍可按元数据自动允许（选「按副作用」时）。',
          style: TextStyle(
            fontSize: 12,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 8),
        ComboBox<String>(
          value: value?.wire ?? 'side_effect',
          isExpanded: true,
          items: [
            const ComboBoxItem(
              value: 'side_effect',
              child: Text('按副作用 / 元数据（推荐）'),
            ),
            ComboBoxItem(
              value: McpToolPolicyLevel.deny.wire,
              child: Text(_levelShort(McpToolPolicyLevel.deny)),
            ),
            ComboBoxItem(
              value: McpToolPolicyLevel.confirmAlways.wire,
              child: Text(_levelShort(McpToolPolicyLevel.confirmAlways)),
            ),
            ComboBoxItem(
              value: McpToolPolicyLevel.confirmOnce.wire,
              child: Text(_levelShort(McpToolPolicyLevel.confirmOnce)),
            ),
            ComboBoxItem(
              value: McpToolPolicyLevel.autoAllow.wire,
              child: Text(_levelShort(McpToolPolicyLevel.autoAllow)),
            ),
          ],
          onChanged: (v) {
            if (v == null || v == 'side_effect') {
              onChanged(null);
            } else {
              onChanged(McpToolPolicyLevel.tryParse(v));
            }
          },
        ),
      ],
    );
  }
}

class _ToolsPolicyTable extends StatelessWidget {
  const _ToolsPolicyTable({
    required this.tokens,
    required this.tools,
    required this.defaultToolPolicy,
    required this.overrides,
    required this.onPolicyChanged,
  });

  final FluentTokens tokens;
  final List<McpToolDescriptor> tools;
  final McpToolPolicyLevel? defaultToolPolicy;
  final Map<String, McpToolPolicyLevel> overrides;
  final void Function(String toolName, McpToolPolicyLevel? level)
      onPolicyChanged;

  static String _sideLabel(McpToolSideEffect s) => switch (s) {
        McpToolSideEffect.read => '读',
        McpToolSideEffect.write => '写',
        McpToolSideEffect.unknown => '未知',
      };

  static String _policyLabel(
    McpToolPolicyLevel? level,
    McpToolDescriptor tool,
    McpToolPolicyLevel? serverDefault,
  ) {
    if (level == null) {
      final effective = const McpToolPolicyResolver().resolve(
        server: McpServerConfig(
          id: '',
          displayName: '',
          defaultToolPolicy: serverDefault,
        ),
        tool: tool,
        overrides: const {},
      );
      final prefix = serverDefault != null ? 'Server 默认' : '默认';
      return '$prefix（${_levelShort(effective)}）';
    }
    return _levelShort(level);
  }

  static String _levelShort(McpToolPolicyLevel level) => switch (level) {
        McpToolPolicyLevel.deny => '拒绝',
        McpToolPolicyLevel.confirmAlways => '每次确认',
        McpToolPolicyLevel.confirmOnce => '本会话确认一次',
        McpToolPolicyLevel.autoAllow => '自动允许',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '按工具覆盖（可选）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 8),
        for (final tool in tools) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tool.displayTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _sideLabel(tool.sideEffect),
                        style: TextStyle(
                          fontSize: 10,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
                if (tool.name != tool.displayTitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    tool.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ],
                if (tool.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    tool.description!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkSecondary,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '授权',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ComboBox<String>(
                        value: overrides.containsKey(tool.name)
                            ? overrides[tool.name]!.wire
                            : 'default',
                        isExpanded: true,
                        items: [
                          ComboBoxItem(
                            value: 'default',
                            child: Text(
                              _policyLabel(null, tool, defaultToolPolicy),
                            ),
                          ),
                          const ComboBoxItem(
                            value: 'deny',
                            child: Text('拒绝'),
                          ),
                          const ComboBoxItem(
                            value: 'confirm_always',
                            child: Text('每次确认'),
                          ),
                          const ComboBoxItem(
                            value: 'confirm_once',
                            child: Text('本会话确认一次'),
                          ),
                          const ComboBoxItem(
                            value: 'auto_allow',
                            child: Text('自动允许'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          if (v == 'default') {
                            onPolicyChanged(tool.name, null);
                          } else {
                            onPolicyChanged(
                              tool.name,
                              McpToolPolicyLevel.tryParse(v),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
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
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(10),
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
              color: tokens.ink,
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
            color: tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
