import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'empty_illustrations.dart';
import 'fluent_empty_states.dart';

class SessionListItem {
  const SessionListItem({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}

class SessionListPane extends StatelessWidget {
  const SessionListPane({
    super.key,
    required this.sessions,
    required this.onSelect,
    required this.onCreate,
    this.selectedId,
    this.busySessionId,
    this.onDelete,
    this.onRename,
    this.headerTitle = '会话',
  });

  final List<SessionListItem> sessions;
  final String? selectedId;
  final String? busySessionId;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onDelete;
  final Future<void> Function(String id, String title)? onRename;
  final String headerTitle;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(FluentTheme.of(context).visualDensity);
    final itemVPad = density.sessionItemVerticalPadding;
    final listGap = density.sessionListGap;
    return ColoredBox(
      color: tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              density == UiDensity.compact ? 8 : 12,
              8,
              density == UiDensity.compact ? 6 : 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    headerTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.inkSecondary,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: '新建会话',
                  excludeSemantics: true,
                  child: Tooltip(
                    message: '新建会话',
                    child: IconButton(
                      icon: const Icon(FluentIcons.add, size: 14),
                      onPressed: onCreate,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sessions.isEmpty
                ? FluentSessionListEmpty(
                    onCreate: onCreate,
                    illustration: const FluentEmptyIllustration.noSessions(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final selected = session.id == selectedId;
                      final busy = session.id == busySessionId;
                      return Padding(
                        padding: EdgeInsets.only(bottom: listGap),
                        child: _SessionRow(
                          session: session,
                          selected: selected,
                          busy: busy,
                          itemVPad: itemVPad,
                          onSelect: () => onSelect(session.id),
                          onDelete: onDelete == null
                              ? null
                              : () => onDelete!(session.id),
                          onRename: onRename == null
                              ? null
                              : (title) => onRename!(session.id, title),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.selected,
    required this.busy,
    required this.itemVPad,
    required this.onSelect,
    this.onDelete,
    this.onRename,
  });

  final SessionListItem session;
  final bool selected;
  final bool busy;
  final double itemVPad;
  final VoidCallback onSelect;
  final VoidCallback? onDelete;
  final Future<void> Function(String title)? onRename;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  final FlyoutController _flyout = FlyoutController();
  final TextEditingController _renameCtrl = TextEditingController();
  bool _renaming = false;

  @override
  void dispose() {
    _flyout.dispose();
    _renameCtrl.dispose();
    super.dispose();
  }

  Future<void> _showMenu(Offset globalPosition) async {
    final navBox =
        Navigator.of(context).context.findRenderObject() as RenderBox?;
    if (navBox == null) return;
    final position = navBox.globalToLocal(globalPosition);
    await _flyout.showFlyout<void>(
      position: position,
      barrierDismissible: true,
      dismissWithEsc: true,
      builder: (ctx) {
        return MenuFlyout(
          items: [
            if (widget.onRename != null)
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.rename, size: 14),
                text: const Text('重命名'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _renaming = true;
                    _renameCtrl.text = widget.session.title;
                    _renameCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _renameCtrl.text.length,
                    );
                  });
                },
              ),
            if (widget.onDelete != null)
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.delete, size: 14),
                text: const Text('删除'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  widget.onDelete!();
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _commitRename() async {
    final title = _renameCtrl.text.trim();
    setState(() => _renaming = false);
    if (widget.onRename == null) return;
    if (title == widget.session.title) return;
    await widget.onRename!(title);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final subtitle = widget.session.subtitle?.trim() ?? '';

    final labelParts = <String>[
      widget.session.title,
      if (subtitle.isNotEmpty) subtitle,
      if (widget.busy) '进行中',
      if (widget.selected) '已选中',
    ];

    return FlyoutTarget(
      controller: _flyout,
      child: GestureDetector(
        onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
        child: Semantics(
          button: !_renaming,
          selected: widget.selected,
          label: labelParts.join('，'),
          excludeSemantics: !_renaming,
          child: HoverButton(
            onPressed: _renaming ? null : widget.onSelect,
            cursor: SystemMouseCursors.click,
            builder: (context, states) {
              final hovered = states.isHovered;
              final focused = states.isFocused;
              final Color bg;
              if (widget.selected) {
                bg = tokens.primary.withValues(alpha: 0.10);
              } else if (hovered || focused) {
                bg = tokens.surfaceMuted;
              } else {
                bg = Colors.transparent;
              }
              return Container(
                padding: EdgeInsets.fromLTRB(
                  10,
                  widget.itemVPad,
                  6,
                  widget.itemVPad,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: focused
                      ? Border.all(
                          color: tokens.primary.withValues(alpha: 0.55),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    if (widget.busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: ProgressRing(strokeWidth: 1.5),
                        ),
                      ),
                    Expanded(
                      child: _renaming
                          ? TextBox(
                              controller: _renameCtrl,
                              autofocus: true,
                              onSubmitted: (_) => _commitRename(),
                              suffix: Tooltip(
                                message: '确认重命名',
                                child: Semantics(
                                  button: true,
                                  label: '确认重命名',
                                  excludeSemantics: true,
                                  child: IconButton(
                                    icon: const Icon(
                                      FluentIcons.check_mark,
                                      size: 10,
                                    ),
                                    onPressed: _commitRename,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: widget.selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: tokens.ink,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: tokens.inkMuted,
                                      fontFamily: tokens.fontFamily,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    if (!_renaming &&
                        widget.onDelete != null &&
                        (hovered || focused || widget.selected))
                      Tooltip(
                        message: '删除会话',
                        child: Semantics(
                          button: true,
                          label: '删除会话 ${widget.session.title}',
                          excludeSemantics: true,
                          child: IconButton(
                            icon: Icon(
                              FluentIcons.delete,
                              size: 12,
                              color: tokens.inkMuted,
                            ),
                            onPressed: widget.onDelete,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
