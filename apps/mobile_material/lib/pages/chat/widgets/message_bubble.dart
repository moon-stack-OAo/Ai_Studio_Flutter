import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../image/widgets/image_lightbox.dart';
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

  Future<void> _openAttachmentLightbox(BuildContext context, int index) async {
    final refs = message.attachments;
    if (refs.isEmpty) return;
    final start = index.clamp(0, refs.length - 1);
    await ImageLightbox.show(
      context,
      ref: refs[start],
      source: ImageLightboxSource.attachment,
      loadBytes: () => _loadAttachmentBytes(refs[start]),
    );
  }

  Future<Uint8List?> _loadAttachmentBytes(ImageRef ref) async {
    try {
      if (ref.type == ImageRefType.file) {
        final file = File(ref.src);
        if (await file.exists()) return file.readAsBytes();
      }
      if (ref.type == ImageRefType.b64 && ref.src.isNotEmpty) {
        return Uint8List.fromList(base64Decode(ref.src));
      }
    } catch (_) {}
    return null;
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
    final attachments = isUser ? message.attachments : const <ImageRef>[];
    final hasAttachments = attachments.isNotEmpty;
    final showUserText = isUser && bodyText.isNotEmpty;

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
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasAttachments) ...[
                            _ChatAttachmentThumbs(
                              refs: attachments,
                              onTap: (i) =>
                                  _openAttachmentLightbox(context, i),
                            ),
                            if (showUserText) const SizedBox(height: 8),
                          ],
                          if (showUserText)
                            SelectableText(
                              bodyText,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color:
                                    message.error ? tokens.danger : tokens.ink,
                                fontFamily: tokens.fontFamily,
                              ),
                            )
                          else if (!hasAttachments)
                            SelectableText(
                              message.content.isEmpty && message.streaming
                                  ? '…'
                                  : (message.content.isEmpty && message.error
                                      ? (message.errorMessage ?? '出错了')
                                      : message.content),
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.55,
                                color:
                                    message.error ? tokens.danger : tokens.ink,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                        ],
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

/// 对话气泡附图缩略（CHAT-ATTACH；独立于生图 TURN-REF）。
class _ChatAttachmentThumbs extends StatelessWidget {
  const _ChatAttachmentThumbs({
    required this.refs,
    this.onTap,
  });

  final List<ImageRef> refs;
  final ValueChanged<int>? onTap;

  static const double _size = 72;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final shown = refs.length > maxChatAttachments
        ? refs.sublist(0, maxChatAttachments)
        : refs;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (var index = 0; index < shown.length; index++)
          Semantics(
            button: onTap != null,
            label: '附图 ${index + 1}',
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(index),
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    border: Border.all(color: tokens.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _ChatAttachmentThumb(ref: shown[index]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatAttachmentThumb extends StatefulWidget {
  const _ChatAttachmentThumb({required this.ref});

  final ImageRef ref;

  @override
  State<_ChatAttachmentThumb> createState() => _ChatAttachmentThumbState();
}

class _ChatAttachmentThumbState extends State<_ChatAttachmentThumb> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChatAttachmentThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.src != widget.ref.src ||
        oldWidget.ref.type != widget.ref.type) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _bytes = null;
    });
    try {
      if (widget.ref.type == ImageRefType.url) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (widget.ref.type == ImageRefType.file) {
        final f = File(widget.ref.src);
        if (await f.exists()) {
          final b = await f.readAsBytes();
          if (mounted) {
            setState(() {
              _bytes = b;
              _loading = false;
            });
          }
          return;
        }
      }
      if (widget.ref.type == ImageRefType.b64 && widget.ref.src.isNotEmpty) {
        final b = Uint8List.fromList(base64Decode(widget.ref.src));
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes != null && _bytes!.isNotEmpty) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(
        widget.ref.src,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 20,
            color: tokens.inkMuted,
          ),
        ),
      );
    }
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: tokens.inkMuted,
      ),
    );
  }
}
