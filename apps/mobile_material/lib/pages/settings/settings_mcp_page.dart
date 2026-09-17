import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/back_to_top_host.dart';
import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';
import 'mcp_edit_sheet.dart';

/// SET-MCP：业务 MCP Server 列表（设置 → 提供商 Tab 内入口推入）。
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
  McpServerRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addServer() async {
    final id = await _repo.add(
      displayName: '新 MCP Server',
      baseUrl: '',
      enabled: true,
    );
    if (!mounted) return;
    _snack('已添加 MCP Server');
    await showMcpEditSheet(
      context: context,
      repository: _repo,
      sessionFactory: widget.sessionFactory,
      serverId: id,
    );
    if (mounted) setState(() {});
  }

  Future<void> _importJson() async {
    final jsonCtrl = TextEditingController();
    McpConfigImportResult? preview;
    String? parseHint;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('导入 MCP 配置 JSON'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '粘贴 mcpServers / OpenCode mcp。移动端仅导入 HTTP；stdio 会跳过。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: jsonCtrl,
                        maxLines: 10,
                        decoration: const InputDecoration(
                          hintText: '{ "mcpServers": { … } }',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (preview != null || parseHint != null) {
                            setLocal(() {
                              preview = null;
                              parseHint = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          final r = parseMcpConfigJson(
                            jsonCtrl.text,
                            allowStdio: false,
                          );
                          setLocal(() {
                            preview = r;
                            if (r.hasErrors) {
                              parseHint = r.errors.join('；');
                            } else if (!r.hasEntries) {
                              parseHint = r.skipped.isEmpty
                                  ? '没有可导入的 Server'
                                  : '没有可导入项（已跳过 ${r.skipped.length} 个；stdio 仅桌面）';
                            } else {
                              parseHint = null;
                            }
                          });
                        },
                        child: const Text('解析预览'),
                      ),
                      if (parseHint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          parseHint!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      ],
                      if (preview != null && preview!.hasEntries) ...[
                        const SizedBox(height: 10),
                        Text(
                          '将导入 ${preview!.entries.length} 个'
                          '${preview!.skipped.isNotEmpty ? '，跳过 ${preview!.skipped.length} 个' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final e in preview!.entries)
                          Text(
                            '· ${e.name} · ${e.draft.baseUrl}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: preview != null && preview!.hasEntries
                      ? () => Navigator.pop(dialogCtx, true)
                      : null,
                  child: const Text('导入'),
                ),
              ],
            );
          },
        );
      },
    );

    final result = preview;
    jsonCtrl.dispose();
    if (confirmed != true || result == null || !result.hasEntries) return;
    if (!mounted) return;

    final existingNames =
        _repo.servers.map((s) => s.displayName).toList(growable: true);
    var imported = 0;
    for (final e in result.entries) {
      final displayName =
          uniqueMcpImportDisplayName(e.draft.displayName, existingNames);
      existingNames.add(displayName);
      final d = e.draft;
      final token = e.bearerToken?.trim();
      await _repo.add(
        displayName: displayName,
        baseUrl: d.baseUrl,
        transport: McpTransport.http,
        authKind: token != null && token.isNotEmpty
            ? McpAuthKind.bearer
            : d.authKind,
        bearerToken: token,
        enabled: d.enabled,
      );
      imported++;
    }
    if (!mounted) return;
    final skipN = result.skipped.length;
    _snack(
      skipN > 0 ? '已导入 $imported 个，跳过 $skipN 个' : '已导入 $imported 个 MCP Server',
    );
    setState(() {});
  }

  Future<void> _openEditor(String id) async {
    await showMcpEditSheet(
      context: context,
      repository: _repo,
      sessionFactory: widget.sessionFactory,
      serverId: id,
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(McpServerConfig server) async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除此 MCP Server？',
      message: '将删除「${server.displayName}」及其本机 Token，此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!ok) return;
    await _repo.delete(server.id);
    if (!mounted) return;
    _snack('已删除');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final servers = _repo.servers;

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('业务 MCP'),
      ),
      body: BackToTopHost(
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Text(
              '配置业务 MCP Server 后，对话模型可调用其 tools。元数据存本机；Bearer Token 存 OS 凭据库。',
              style: TextStyle(fontSize: 12, color: tokens.inkMuted),
            ),
            const SizedBox(height: 12),
            if (servers.isEmpty)
              MaterialContentEmpty(
                hint: '尚未配置 MCP Server',
                subtitle: '添加业务 MCP 后，对话模型可调用其 tools。',
                illustration: const MaterialEmptyIllustration.noProviders(),
                actionLabel: '添加 Server',
                onAction: _addServer,
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < servers.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: tokens.border),
                      _McpListTile(
                        server: servers[i],
                        onTap: () => _openEditor(servers[i].id),
                        onDelete: () => _delete(servers[i]),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addServer,
              icon: const Icon(Icons.add),
              label: const Text('添加 Server'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: tokens.border),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _importJson,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('导入 JSON'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: tokens.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpListTile extends StatelessWidget {
  const _McpListTile({
    required this.server,
    required this.onTap,
    required this.onDelete,
  });

  final McpServerConfig server;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);

    final isStdio = server.transport == McpTransport.stdio;

    late final String pill;
    late final Color pillFg;
    late final Color pillBg;
    if (isStdio) {
      pill = '仅桌面';
      pillFg = tokens.inkMuted;
      pillBg = tokens.surfaceMuted;
    } else if (!server.enabled) {
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
    } else if (!server.hasBaseUrl) {
      pill = '待配置';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    } else {
      pill = '待探测';
      pillFg = tokens.primaryPressed;
      pillBg = Color.lerp(tokens.primary, tokens.surface, 0.88)!;
    }

    final meta = isStdio
        ? '本地 stdio，仅桌面可用'
        : (server.baseUrl.trim().isNotEmpty
            ? server.baseUrl.trim()
            : '未填写 Base URL');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      onTap: onTap,
      title: Text(
        server.displayName,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, color: tokens.danger, size: 20),
          ),
        ],
      ),
    );
  }
}
