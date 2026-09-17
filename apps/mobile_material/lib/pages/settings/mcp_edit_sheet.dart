import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/back_to_top_host.dart';

/// SET-MCP-EDIT / SET-MCP-POLICY：MCP Server 编辑 BottomSheet，底栏固定保存/取消。
Future<void> showMcpEditSheet({
  required BuildContext context,
  required McpServerRepository repository,
  required McpSessionFactory sessionFactory,
  required String serverId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      return _McpEditSheet(
        repository: repository,
        sessionFactory: sessionFactory,
        serverId: serverId,
      );
    },
  );
}

class _McpEditSheet extends StatefulWidget {
  const _McpEditSheet({
    required this.repository,
    required this.sessionFactory,
    required this.serverId,
  });

  final McpServerRepository repository;
  final McpSessionFactory sessionFactory;
  final String serverId;

  @override
  State<_McpEditSheet> createState() => _McpEditSheetState();
}

class _McpEditSheetState extends State<_McpEditSheet> {
  late String _serverId;
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  McpAuthKind _authKind = McpAuthKind.none;
  bool _enabled = true;
  bool _obscureToken = true;
  bool _hasStoredToken = false;
  bool _probing = false;
  String? _statusText;
  bool _statusOk = false;
  bool _dirty = false;
  bool _syncingForm = false;

  McpServerRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _serverId = widget.serverId;
    _repo.addListener(_onRepoChanged);
    _baseUrlCtrl.addListener(_onFieldsChanged);
    _nameCtrl.addListener(_onFieldsChanged);
    _tokenCtrl.addListener(_onFieldsChanged);
    _loadFormFromSelected();
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    _baseUrlCtrl.removeListener(_onFieldsChanged);
    _nameCtrl.removeListener(_onFieldsChanged);
    _tokenCtrl.removeListener(_onFieldsChanged);
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    if (!mounted || _syncingForm) return;
    _markDirty();
    setState(() {});
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final exists = _repo.servers.any((s) => s.id == _serverId);
    if (!exists) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  McpServerConfig? get _selected => _repo.findById(_serverId);

  Future<void> _loadFormFromSelected() async {
    final s = _selected;
    _syncingForm = true;
    if (s == null) {
      _nameCtrl.clear();
      _baseUrlCtrl.clear();
      _tokenCtrl.clear();
      _authKind = McpAuthKind.none;
      _enabled = true;
      _hasStoredToken = false;
      _statusText = null;
      _dirty = false;
    } else {
      _nameCtrl.text = s.displayName;
      _baseUrlCtrl.text = s.baseUrl;
      _tokenCtrl.clear();
      _authKind =
          s.authKind == McpAuthKind.oauth ? McpAuthKind.none : s.authKind;
      _enabled = s.enabled;
      _hasStoredToken = await _repo.hasBearerSecret(s.id);
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

  void _snack(String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _save() async {
    final current = _selected;
    if (current == null) return false;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写显示名称', error: true);
      return false;
    }
    if (current.transport == McpTransport.stdio) {
      var next = current.copyWith(
        displayName: name,
        enabled: false,
      );
      await _repo.update(next);
      await _loadFormFromSelected();
      if (!mounted) return false;
      _snack('已保存名称；stdio 在移动端不可用，已保持停用');
      return true;
    }
    final baseUrl = _baseUrlCtrl.text.trim();
    if (baseUrl.isNotEmpty) {
      try {
        assertSafeHttpUrl(Uri.parse(baseUrl));
      } on UrlSafetyException catch (e) {
        _snack(e.message, error: true);
        return false;
      } catch (_) {
        _snack('Base URL 无效', error: true);
        return false;
      }
    }
    final urlRisk = warnUnsafeUrl(baseUrl);
    var next = current.copyWith(
      displayName: name,
      baseUrl: baseUrl,
      enabled: _enabled,
      authKind: _authKind,
    );

    if (_authKind == McpAuthKind.none) {
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
          baseUrl: baseUrl,
          enabled: _enabled,
          authKind: McpAuthKind.bearer,
        );
      } else if (!_hasStoredToken) {
        _snack('Bearer 鉴权请填写 Token', error: true);
        return false;
      } else {
        next = next.copyWith(authKind: McpAuthKind.bearer);
      }
    }

    await _repo.update(next);
    _tokenCtrl.clear();
    await _loadFormFromSelected();
    if (!mounted) return false;
    _snack('已保存');
    if (urlRisk != null) {
      _snack(urlRisk);
    }
    return true;
  }

  void _cancelEdits() {
    _loadFormFromSelected();
  }

  Future<void> _delete() async {
    final current = _selected;
    if (current == null) return;
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除此 MCP Server？',
      message: '将删除「${current.displayName}」及其本机 Token，此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!ok) return;
    await _repo.delete(current.id);
    if (!mounted) return;
    _snack('已删除');
    Navigator.of(context).pop();
  }

  bool get _isStdioUnsupported =>
      _selected?.transport == McpTransport.stdio;

  bool get _canProbe =>
      !_isStdioUnsupported && _baseUrlCtrl.text.trim().isNotEmpty;

  Future<void> _probeAndRefreshTools() async {
    final current = _selected;
    if (current == null) return;
    if (_isStdioUnsupported) {
      _snack('此 Server 为本地 stdio，仅桌面可用', error: true);
      return;
    }
    if (!_canProbe) {
      _snack('请先填写 Base URL', error: true);
      return;
    }
    if (_dirty) {
      final saved = await _save();
      if (!saved) return;
    }
    final server = _repo.findById(current.id);
    if (server == null || !server.hasBaseUrl) {
      _snack('请先保存有效的 Base URL', error: true);
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
        _snack('已刷新 ${tools.length} 个工具');
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
        _snack(msg, error: true);
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
      _snack('探测失败：$msg', error: true);
    } finally {
      try {
        session?.close();
      } catch (_) {}
    }
  }

  Future<void> _setToolPolicy(String toolName, McpToolPolicyLevel? level) async {
    await _repo.setToolPolicyOverride(_serverId, toolName, level);
  }

  Future<void> _setDefaultToolPolicy(McpToolPolicyLevel? level) async {
    await _repo.setDefaultToolPolicy(_serverId, level);
  }

  Future<void> _tryClose() async {
    if (!_dirty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final discard = await showMaterialConfirmDialog(
      context: context,
      title: '放弃未保存更改？',
      message: '当前表单有未保存修改，关闭将丢失这些更改。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃',
    );
    if (discard && mounted) Navigator.of(context).maybePop();
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
                        '编辑 MCP Server',
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
                child: BackToTopHost(
                  builder: (context, scroll) => ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(
                        '元数据存本机；Bearer Token 存 OS 凭据库。仅支持 HTTP/SSE（Streamable JSON-RPC）。本地 stdio 仅桌面可用。',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkMuted,
                        ),
                      ),
                      if (_isStdioUnsupported) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Color.lerp(
                            tokens.danger,
                            tokens.surface,
                            0.9,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              '此 Server 为本地 stdio，仅桌面可用。移动端无法探测或调用；请在桌面端管理，或改用 HTTP/SSE。',
                              style: TextStyle(
                                fontSize: 13,
                                color: tokens.danger,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
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
                          hintText: '例如 业务查询 MCP',
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: 12),
                      if (_isStdioUnsupported)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '传输方式',
                            helperText: '只读；移动端不支持本地子进程',
                          ),
                          child: Text(
                            '本地 stdio（仅桌面）',
                            style: TextStyle(
                              fontSize: 14,
                              color: tokens.inkMuted,
                            ),
                          ),
                        )
                      else
                        TextField(
                          controller: _baseUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'https://mcp.example.com/mcp',
                            helperText: 'MCP 单一入口，如 https://host/mcp',
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用'),
                        subtitle: Text(
                          _isStdioUnsupported
                              ? '本地 stdio 仅桌面可用，移动端不可启用'
                              : (_enabled ? '对话可暴露其 tools' : '已停用，不参与对话'),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkMuted,
                          ),
                        ),
                        value: _isStdioUnsupported ? false : _enabled,
                        onChanged: _isStdioUnsupported
                            ? null
                            : (v) {
                                setState(() {
                                  _enabled = v;
                                  _dirty = true;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '鉴权',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<McpAuthKind>(
                        key: ValueKey(_authKind),
                        initialValue: _authKind == McpAuthKind.oauth
                            ? McpAuthKind.none
                            : _authKind,
                        decoration: const InputDecoration(labelText: '鉴权方式'),
                        items: const [
                          DropdownMenuItem(
                            value: McpAuthKind.none,
                            child: Text('无鉴权'),
                          ),
                          DropdownMenuItem(
                            value: McpAuthKind.bearer,
                            child: Text('Bearer Token'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _authKind = v;
                            _dirty = true;
                            if (v != McpAuthKind.bearer) {
                              _tokenCtrl.clear();
                            }
                          });
                        },
                      ),
                      if (_authKind == McpAuthKind.bearer) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _tokenCtrl,
                          obscureText: _obscureToken,
                          decoration: InputDecoration(
                            labelText: 'Bearer Token',
                            hintText: _hasStoredToken ? '••••••••' : 'token…',
                            helperText: _hasStoredToken &&
                                    _tokenCtrl.text.isEmpty
                                ? '已保存（留空保持不变）'
                                : null,
                            suffixIcon: IconButton(
                              tooltip: _obscureToken ? '显示' : '隐藏',
                              icon: Icon(
                                _obscureToken
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscureToken = !_obscureToken,
                              ),
                            ),
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        '连接与工具',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.inkSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: (!_canProbe || _probing)
                            ? null
                            : _probeAndRefreshTools,
                        icon: _probing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(_probing ? '探测中…' : '测试连接 / 刷新 tools'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                      if (!_canProbe)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '需先填写 Base URL',
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
                              color: _statusOk ? tokens.success : tokens.danger,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      _ServerDefaultPolicyBlock(
                        value: selected.defaultToolPolicy,
                        onChanged: _setDefaultToolPolicy,
                      ),
                      const SizedBox(height: 14),
                      if (selected.toolsCache.isEmpty)
                        Text(
                          '尚未拉取工具列表。保存 URL 后点「测试连接 / 刷新 tools」。',
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.inkMuted,
                          ),
                        )
                      else
                        _ToolsPolicyList(
                          tools: selected.toolsCache,
                          defaultToolPolicy: selected.defaultToolPolicy,
                          overrides: selected.toolPolicyOverrides,
                          onPolicyChanged: _setToolPolicy,
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除此 Server'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          foregroundColor: tokens.danger,
                          side: BorderSide(color: tokens.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _dirty ? _cancelEdits : null,
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _dirty
                              ? () async {
                                  final nav = Navigator.of(context);
                                  final ok = await _save();
                                  if (ok && mounted) {
                                    nav.maybePop();
                                  }
                                }
                              : null,
                          child: const Text('保存'),
                        ),
                      ),
                    ],
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

class _ServerDefaultPolicyBlock extends StatelessWidget {
  const _ServerDefaultPolicyBlock({
    required this.value,
    required this.onChanged,
  });

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
    final tokens = materialTokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '本 Server 默认授权',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '未单独覆盖的工具走此默认；选「按副作用」时读操作仍可自动允许。',
          style: TextStyle(
            fontSize: 12,
            color: tokens.inkMuted,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(value?.wire ?? 'side_effect'),
          initialValue: value?.wire ?? 'side_effect',
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(
              value: 'side_effect',
              child: Text('按副作用 / 元数据（推荐）'),
            ),
            DropdownMenuItem(
              value: McpToolPolicyLevel.deny.wire,
              child: Text(_levelShort(McpToolPolicyLevel.deny)),
            ),
            DropdownMenuItem(
              value: McpToolPolicyLevel.confirmAlways.wire,
              child: Text(_levelShort(McpToolPolicyLevel.confirmAlways)),
            ),
            DropdownMenuItem(
              value: McpToolPolicyLevel.confirmOnce.wire,
              child: Text(_levelShort(McpToolPolicyLevel.confirmOnce)),
            ),
            DropdownMenuItem(
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

class _ToolsPolicyList extends StatelessWidget {
  const _ToolsPolicyList({
    required this.tools,
    required this.defaultToolPolicy,
    required this.overrides,
    required this.onPolicyChanged,
  });

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

  static String _levelShort(McpToolPolicyLevel level) => switch (level) {
        McpToolPolicyLevel.deny => '拒绝',
        McpToolPolicyLevel.confirmAlways => '每次确认',
        McpToolPolicyLevel.confirmOnce => '本会话确认一次',
        McpToolPolicyLevel.autoAllow => '自动允许',
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

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '按工具覆盖（可选）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
          ),
        ),
        const SizedBox(height: 8),
        for (final tool in tools)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.canvas,
              borderRadius: BorderRadius.circular(10),
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
                        ),
                      ),
                    ),
                  ],
                ),
                if (tool.name != tool.displayTitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    tool.name,
                    style: TextStyle(fontSize: 11, color: tokens.inkMuted),
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
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: overrides.containsKey(tool.name)
                      ? overrides[tool.name]!.wire
                      : 'default',
                  decoration: const InputDecoration(
                    labelText: '授权',
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text(
                        _policyLabel(null, tool, defaultToolPolicy),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 'deny',
                      child: Text('拒绝'),
                    ),
                    const DropdownMenuItem(
                      value: 'confirm_always',
                      child: Text('每次确认'),
                    ),
                    const DropdownMenuItem(
                      value: 'confirm_once',
                      child: Text('本会话确认一次'),
                    ),
                    const DropdownMenuItem(
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
              ],
            ),
          ),
      ],
    );
  }
}
