import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../../widgets/material_empty_states.dart';

/// M-SessionList：全屏会话列表层；系统返回先 pop。
class SessionListPage extends StatelessWidget {
  const SessionListPage({
    super.key,
    required this.sessions,
    required this.activeId,
    required this.onSelect,
    required this.onCreate,
    required this.onDelete,
    this.onRename,
    this.streamingSessionId,
  });

  final List<ChatSession> sessions;
  final String activeId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<String> onDelete;
  final Future<void> Function(String id, String title)? onRename;
  final String? streamingSessionId;

  Future<void> _confirmDelete(BuildContext context, ChatSession session) async {
    final ok = await showMaterialConfirmDialog(
      context: context,
      title: '删除会话',
      message: '确定删除「${session.title}」？',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (ok) onDelete(session.id);
  }

  Future<void> _rename(BuildContext context, ChatSession session) async {
    final rename = onRename;
    if (rename == null) return;
    final ctrl = TextEditingController(text: session.title);
    ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: ctrl.text.length,
    );
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('重命名会话'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 1,
            decoration: const InputDecoration(
              hintText: '会话标题',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (next == null) return;
    if (next == session.title) return;
    await rename(session.id, next);
  }

  Future<void> _showActions(BuildContext context, ChatSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('长按操作'),
              ),
              if (onRename != null)
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _rename(context, session);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除会话…'),
                textColor: Theme.of(ctx).colorScheme.error,
                iconColor: Theme.of(ctx).colorScheme.error,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmDelete(context, session);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(Theme.of(context).visualDensity);
    final itemVPad = density.sessionItemVerticalPadding;
    final separator = density.sessionListSeparator;

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: const Text('会话'),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          onCreate();
          Navigator.of(context).pop();
        },
        tooltip: '新建会话',
        child: const Icon(Icons.add),
      ),
      body: sessions.isEmpty
          ? MaterialSessionListEmpty(
              onCreate: () {
                onCreate();
                Navigator.of(context).pop();
              },
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: sessions.length,
              separatorBuilder: (context, index) => SizedBox(height: separator),
              itemBuilder: (context, index) {
                final session = sessions[index];
                final selected = session.id == activeId;
                final streaming = session.id == streamingSessionId;
                return Material(
                  color: selected ? tokens.surfaceElevated : tokens.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      onSelect(session.id);
                      Navigator.of(context).pop();
                    },
                    onLongPress: () => _showActions(context, session),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: itemVPad,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? tokens.primary.withValues(alpha: 0.35)
                              : tokens.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: tokens.ink,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  streaming ? '流式中' : '本地会话',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: streaming
                                        ? tokens.primary
                                        : tokens.inkMuted,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(
                              Icons.check_circle,
                              color: tokens.primary,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
