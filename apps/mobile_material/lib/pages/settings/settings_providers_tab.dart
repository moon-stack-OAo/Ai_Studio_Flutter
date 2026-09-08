import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/empty_illustrations.dart';
import '../../widgets/material_empty_states.dart';
import 'provider_edit_sheet.dart';

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

  ProviderRepository get _repo => widget.repository;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChanged);
    _selectedId = _repo.activeProviderId;
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (!mounted) return;
    final exists = _repo.providers.any((p) => p.id == _selectedId);
    if (!exists) {
      _selectedId = _repo.activeProviderId;
    }
    setState(() {});
  }

  void _snack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectProvider(String id) async {
    setState(() => _selectedId = id);
    await _repo.setActiveProvider(id);
  }

  Future<void> _openEditor() async {
    final id = _selectedId;
    if (id == null) return;
    await showProviderEditSheet(
      context: context,
      repository: _repo,
      providerId: id,
    );
    if (mounted) setState(() {});
  }

  Future<void> _addProvider() async {
    final created = await _repo.addProvider();
    if (!mounted) return;
    setState(() => _selectedId = created.id);
    _snack('已添加自定义提供商');
    await showProviderEditSheet(
      context: context,
      repository: _repo,
      providerId: created.id,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final providers = _repo.providers;
    final canEdit = _selectedId != null &&
        providers.any((p) => p.id == _selectedId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
          '点选切换当前提供商，再点「编辑」打开抽屉',
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
        if (providers.isNotEmpty) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: canEdit ? _openEditor : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑所选提供商'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
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
