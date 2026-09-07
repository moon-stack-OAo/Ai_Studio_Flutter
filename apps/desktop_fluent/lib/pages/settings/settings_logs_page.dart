import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class SettingsLogsPage extends StatefulWidget {
  const SettingsLogsPage({super.key, required this.repository});

  final AppLogRepository repository;

  @override
  State<SettingsLogsPage> createState() => _SettingsLogsPageState();
}

class _SettingsLogsPageState extends State<SettingsLogsPage> {
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

  Future<void> _copyVisible() async {
    final list = _visible;
    final text = _repo.formatVisible(list);
    if (text.isEmpty) {
      _showInfoBar('暂无可见日志可复制', InfoBarSeverity.warning);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _showInfoBar('已复制 ${list.length} 条可见日志', InfoBarSeverity.success);
  }

  Future<void> _clear() async {
    if (_repo.totalCount == 0) {
      _showInfoBar('暂无日志', InfoBarSeverity.info);
      return;
    }
    final ok = await showFluentConfirmDialog(
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
      _showInfoBar('已清空日志', InfoBarSeverity.success);
    } catch (e) {
      if (!mounted) return;
      _showInfoBar('清空失败：$e', InfoBarSeverity.error);
    }
  }

  Color _levelColor(FluentTokens tokens, AppLogLevel level) {
    return switch (level) {
      AppLogLevel.error => tokens.danger,
      AppLogLevel.warn => tokens.warning,
      AppLogLevel.info => tokens.primary,
      AppLogLevel.debug => tokens.inkMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final visible = _visible;
        final total = _repo.totalCount;
        return ColoredBox(
          color: tokens.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '运行日志',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '采集本机关键事件；对话 / 生图 / 生视频错误会写入。日志不得含密钥明文。',
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Toolbar(
                      tokens: tokens,
                      exactLevel: _exactLevel,
                      source: _source,
                      searchCtrl: _searchCtrl,
                      onLevelChanged: (v) => setState(() => _exactLevel = v),
                      onSourceChanged: (v) => setState(() => _source = v),
                      onSearchChanged: (v) => setState(() => _search = v),
                      onCopy: _copyVisible,
                      onClear: _clear,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '共 $total 条 · 可见 ${visible.length} · 最新在上',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.border),
                    ),
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              '暂无日志',
                              style: TextStyle(
                                fontSize: 14,
                                color: tokens.inkMuted,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            itemCount: visible.length,
                            separatorBuilder: (context, index) => Divider(
                              style: DividerThemeData(
                                decoration: BoxDecoration(
                                  color: tokens.border.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            itemBuilder: (context, index) {
                              final e = visible[index];
                              final lvColor = _levelColor(tokens, e.level);
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: SelectableText.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.45,
                                      color: tokens.ink,
                                    ).withMonoFont(tokens),
                                    children: [
                                      TextSpan(
                                        text: AppLogRepository.formatTimestamp(
                                          e.at,
                                        ),
                                        style: TextStyle(
                                          color: tokens.inkMuted,
                                        ).withMonoFont(tokens),
                                      ),
                                      TextSpan(
                                        text: ' · ',
                                        style: TextStyle(
                                          color: tokens.inkMuted,
                                        ),
                                      ),
                                      TextSpan(
                                        text: e.level.label,
                                        style: TextStyle(
                                          color: lvColor,
                                          fontWeight: FontWeight.w700,
                                        ).withMonoFont(tokens),
                                      ),
                                      TextSpan(
                                        text: ' · ${e.source} · ${e.message}',
                                        style: TextStyle(
                                          color: tokens.ink,
                                        ).withMonoFont(tokens),
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
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  static const Object _allLevels = Object();
  static const String _allSources = '__all_sources__';

  const _Toolbar({
    required this.tokens,
    required this.exactLevel,
    required this.source,
    required this.searchCtrl,
    required this.onLevelChanged,
    required this.onSourceChanged,
    required this.onSearchChanged,
    required this.onCopy,
    required this.onClear,
  });

  final FluentTokens tokens;
  final AppLogLevel? exactLevel;
  final String? source;
  final TextEditingController searchCtrl;
  final ValueChanged<AppLogLevel?> onLevelChanged;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCopy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 140,
          child: ComboBox<Object>(
            // Fluent ComboBox 对 null value 常不渲染选中文案，用哨兵表示「全部」。
            value: exactLevel ?? _allLevels,
            isExpanded: true,
            items: [
              const ComboBoxItem<Object>(
                value: _allLevels,
                child: Text('全部级别'),
              ),
              for (final lv in AppLogLevel.values)
                ComboBoxItem<Object>(
                  value: lv,
                  child: Text(lv.label),
                ),
            ],
            onChanged: (v) {
              if (v == null || identical(v, _allLevels)) {
                onLevelChanged(null);
              } else {
                onLevelChanged(v as AppLogLevel);
              }
            },
          ),
        ),
        SizedBox(
          width: 140,
          child: ComboBox<String>(
            value: source ?? _allSources,
            isExpanded: true,
            items: [
              const ComboBoxItem<String>(
                value: _allSources,
                child: Text('全部来源'),
              ),
              for (final s in AppLogSources.all)
                ComboBoxItem<String>(
                  value: s,
                  child: Text(AppLogSources.labelZh(s)),
                ),
            ],
            onChanged: (v) {
              if (v == null || v == _allSources) {
                onSourceChanged(null);
              } else {
                onSourceChanged(v);
              }
            },
          ),
        ),
        SizedBox(
          width: 240,
          child: TextBox(
            controller: searchCtrl,
            placeholder: '搜索消息…',
            onChanged: onSearchChanged,
          ),
        ),
        Button(
          onPressed: onCopy,
          child: const Text('复制可见'),
        ),
        Tooltip(
          message: '清空全部日志',
          child: Semantics(
            button: true,
            label: '清空全部日志',
            child: Button(
              onPressed: onClear,
              child: const Text('清空…'),
            ),
          ),
        ),
      ],
    );
  }
}
