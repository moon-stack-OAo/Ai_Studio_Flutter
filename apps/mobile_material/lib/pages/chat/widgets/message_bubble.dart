import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'markdown_host.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRecall,
    this.recallEnabled = false,
  });

  final ChatMessage message;
  final VoidCallback? onRecall;
  final bool recallEnabled;

  Future<void> _copy(BuildContext context) async {
    final text = message.content.isEmpty && message.error
        ? (message.errorMessage ?? '出错了')
        : message.content;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final isUser = message.role == ChatRole.user;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _copy(context);
                },
              ),
              if (isUser && recallEnabled && onRecall != null)
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('撤回'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onRecall!();
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
    final isUser = message.role == ChatRole.user;
    final align =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isUser
        ? tokens.primary.withValues(alpha: 0.14)
        : tokens.surface;
    final border = isUser
        ? tokens.primary.withValues(alpha: 0.28)
        : tokens.border;
    final label = isUser ? '你' : '助手';

    final bodyText = message.content.isEmpty && message.streaming
        ? ''
        : (message.content.isEmpty && message.error
            ? (message.errorMessage ?? '出错了')
            : message.content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                if (!isUser) ...[
                  Builder(
                    builder: (_) {
                      final meta = formatChatMessageMeta(
                        model: message.model,
                        latencyMs: message.latencyMs,
                        streaming: message.streaming,
                      );
                      if (meta == null || meta.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          meta,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tokens.inkMuted,
                          ).withMonoFont(tokens),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onLongPress: () => _showActions(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.88,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: isUser
                    ? SelectableText(
                        message.content.isEmpty && message.streaming
                            ? '…'
                            : (message.content.isEmpty && message.error
                                ? (message.errorMessage ?? '出错了')
                                : message.content),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: message.error ? tokens.danger : tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      )
                    : MarkdownHost(
                        data: bodyText,
                        error: message.error,
                      ),
              ),
            ),
          ),
          if (message.stopped)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                '已停止',
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.inkMuted,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
          if (message.error &&
              message.errorMessage != null &&
              message.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                message.errorMessage!,
                style: TextStyle(
                  fontSize: 11,
                  color: tokens.danger,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
