import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsLogsTab extends StatefulWidget {
  const SettingsLogsTab({
    super.key,
    required this.repository,
  });

  final AppLogRepository repository;

  @override
  State<SettingsLogsTab> createState() => _SettingsLogsTabState();
}

class _SettingsLogsTabState extends State<SettingsLogsTab> {
  AppLogLevel? _exactLevel;
  String? _source;
  final _searchCtrl = TextEditingController();
  String _search = '';

  AppLogRepository get _repo => widget.repository;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AppLogEntry> get _visible => _repo.query(
        exactLevel: _exactLevel,
        source: _source,
        search: _search,
      );

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

  Future<void> _copyVisible() async {
    final list = _visible;
    final text = _repo.formatVisible(list);
    if (text.isEmpty) {
      _snack('暂无可见日志可复制');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack('已复制 ${list.length} 条可见日志');
  }

  Future<void> _clear() async {
    if (_repo.totalCount == 0) {
      _snack('暂无日志');
      return;
    }
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '清空全部日志？',
      message: '将删除本机已保存的 ${_repo.totalCount} 条运行日志，此操作不可撤销。',
      confirmLabel: '清空',
      isDestructive: true,
    );
    if (!ok) return;
    try {
      await _repo.clear();
      if (!mounted) return;
      _snack('已清空日志');
    } catch (e) {
      if (!mounted) return;
      _snack('清空失败：$e', error: true);
    }
  }

  Color _levelColor(MaterialTokens tokens, AppLogLevel level) {
    return switch (level) {
      AppLogLevel.error => tokens.danger,
      AppLogLevel.warn => tokens.warning,
      AppLogLevel.info => tokens.primary,
      AppLogLevel.debug => tokens.inkMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final visible = _visible;
        final total = _repo.totalCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '运行日志',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '本机关键事件；生视频每轮轮询会写入。不得含密钥明文。',
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<AppLogLevel?>(
                          key: ValueKey(_exactLevel),
                          initialValue: _exactLevel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '级别',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<AppLogLevel?>(
                              value: null,
                              child: Text('全部级别'),
                            ),
                            for (final lv in AppLogLevel.values)
                              DropdownMenuItem<AppLogLevel?>(
                                value: lv,
                                child: Text(lv.label),
                              ),
                          ],
                          onChanged: (v) => setState(() => _exactLevel = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey(_source),
                          initialValue: _source,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '来源',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('全部来源'),
                            ),
                            for (final s in AppLogSources.all)
                              DropdownMenuItem<String?>(
                                value: s,
                                child: Text(AppLogSources.labelZh(s)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _source = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: '搜索日志',
                      hintText: '搜索消息…',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _copyVisible,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('复制可见'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: '清空全部日志',
                          child: OutlinedButton(
                            onPressed: _clear,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            child: const Text('清空…'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '共 $total 条 · 可见 ${visible.length} · 最新在上',
                    style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      MaterialTokens.dark.surfaceElevated,
                      MaterialTokens.dark.canvas,
                      0.35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.border),
                  ),
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            '暂无日志',
                            style: TextStyle(
                              fontSize: 14,
                              color: MaterialTokens.dark.inkMuted,
                              fontFamily: tokens.fontFamily,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: MaterialTokens.dark.ink
                                .withValues(alpha: 0.08),
                          ),
                          itemBuilder: (context, index) {
                            final e = visible[index];
                            final lvColor = _levelColor(tokens, e.level);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: SelectableText.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.45,
                                    color: MaterialTokens.dark.ink,
                                  ).withMonoFont(tokens),
                                  children: [
                                    TextSpan(
                                      text: AppLogRepository.formatTimestamp(
                                        e.at,
                                      ),
                                      style: TextStyle(
                                        color: MaterialTokens.dark.inkMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const TextSpan(text: '\n'),
                                    TextSpan(
                                      text: e.level.label,
                                      style: TextStyle(
                                        color: lvColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' · ${e.source} · ${e.message}',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
