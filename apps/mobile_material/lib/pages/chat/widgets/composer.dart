import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

import '../chat_controller.dart';

/// M-Composer：底栏输入；IME 由壳藏 Nav + Scaffold resize 抬起；含 CHAT-ATTACH。
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.enabled,
    required this.streaming,
    required this.onSend,
    required this.onStop,
    this.visionSupported = false,
    this.draftAttachments = const [],
    this.onPickAttachments,
    this.onRemoveDraftAttachment,
    this.canSendWithDraft,
  });

  final bool enabled;
  final bool streaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;

  /// 当前对话模型是否支持视觉（启发式）。
  final bool visionSupported;

  final List<ChatDraftAttachment> draftAttachments;
  final VoidCallback? onPickAttachments;
  final ValueChanged<int>? onRemoveDraftAttachment;

  /// 含正文/附图的发送门闩；缺省时退化为 [enabled] + 非空正文。
  final bool Function(String textDraft)? canSendWithDraft;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _textNonEmpty = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final next = _controller.text.trim().isNotEmpty;
    if (next != _textNonEmpty) setState(() => _textNonEmpty = next);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _hasDraft => widget.draftAttachments.isNotEmpty;

  bool get _canSubmitContent {
    final gate = widget.canSendWithDraft;
    if (gate != null) return gate(_controller.text);
    if (!widget.enabled) return false;
    return _controller.text.trim().isNotEmpty || _hasDraft;
  }

  void _submit() {
    if (widget.streaming) {
      widget.onStop();
      return;
    }
    if (!_canSubmitContent) return;
    final text = _controller.text;
    widget.onSend(text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final density =
        UiDensity.fromVisualDensity(Theme.of(context).visualDensity);
    final canType = widget.enabled && !widget.streaming;
    final isDark = tokens.brightness == Brightness.dark;
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    // IME 升起时 padding.bottom 常被清零，用 viewPadding 保留全面屏底 inset。
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
    final basePad = density.composerPadding;
    // Composer 在 NavBar 之上时只需少量余量；Nav 收起后仍跟键盘同相位淡出。
    final safeExtra = bottomSafe * 0.15;
    final safeFade =
        (1.0 - (viewInsetsBottom / (safeExtra + 1.0)).clamp(0.0, 1.0))
            .toDouble();
    final padBottom =
        (density == UiDensity.comfortable ? 10.0 : 8.0) + safeExtra * safeFade;

    final attachTooltip = !widget.visionSupported
        ? '当前模型不支持图片'
        : (widget.draftAttachments.length >= maxChatAttachments
            ? '最多 $maxChatAttachments 张'
            : '附加图片（最多 $maxChatAttachments 张）');
    final canPick = widget.visionSupported &&
        canType &&
        widget.onPickAttachments != null &&
        widget.draftAttachments.length < maxChatAttachments;

    final hintText = widget.streaming
        ? '生成中…'
        : (_hasDraft ? '可空文发送附图…' : '输入消息…');

    return AnimatedContainer(
      duration: MaterialMotion.micro,
      curve: MaterialMotion.standard,
      padding: EdgeInsets.fromLTRB(
        basePad.left,
        basePad.top,
        basePad.right,
        padBottom,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.streaming) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Color.lerp(
                    tokens.primary,
                    tokens.border,
                    isDark ? 0.65 : 0.75,
                  )!,
                ),
              ),
              child: Row(
                children: [
                  _PulseDot(color: tokens.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '流式输出中 · 点停止可中断',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Color.lerp(
                          tokens.primary,
                          tokens.ink,
                          isDark ? 0.35 : 0.55,
                        ),
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_hasDraft) ...[
            _DraftAttachmentStrip(
              drafts: widget.draftAttachments,
              tokens: tokens,
              onRemove: canType ? widget.onRemoveDraftAttachment : null,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Tooltip(
                message: attachTooltip,
                child: Semantics(
                  button: true,
                  enabled: canPick,
                  label: '附加图片',
                  excludeSemantics: true,
                  child: Material(
                    color: canPick
                        ? tokens.surfaceMuted
                        : tokens.surfaceMuted.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canPick ? widget.onPickAttachments : null,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 22,
                          color: canPick
                              ? tokens.inkSecondary
                              : tokens.inkMuted.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: '消息输入',
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    enabled: canType,
                    minLines: 1,
                    maxLines: density == UiDensity.comfortable ? 6 : 5,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: hintText,
                      filled: true,
                      fillColor:
                          isDark ? tokens.surfaceElevated : tokens.canvas,
                      contentPadding: density.composerFieldPadding,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tokens.primary),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: tokens.border),
                      ),
                    ),
                    style: TextStyle(
                      fontFamily: tokens.fontFamily,
                      fontSize: 14,
                      height: 1.45,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: widget.streaming
                    ? Tooltip(
                        message: '停止生成',
                        child: Semantics(
                          button: true,
                          label: '停止生成',
                          excludeSemantics: true,
                          child: FilledButton(
                            onPressed: widget.onStop,
                            style: FilledButton.styleFrom(
                              backgroundColor: tokens.danger,
                              foregroundColor: tokens.onPrimary,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: const Icon(Icons.stop_rounded, size: 22),
                          ),
                        ),
                      )
                    : Tooltip(
                        message: '发送',
                        child: Semantics(
                          button: true,
                          label: '发送消息',
                          excludeSemantics: true,
                          child: FilledButton(
                            onPressed: _canSubmitContent ? _submit : null,
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(48, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: const Icon(Icons.send_rounded, size: 20),
                          ),
                        ),
                      ),
              ),
            ],
          ),
          if (!widget.streaming && !widget.visionSupported) ...[
            const SizedBox(height: 6),
            Text(
              '当前模型不支持附图',
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
    );
  }
}

class _DraftAttachmentStrip extends StatelessWidget {
  const _DraftAttachmentStrip({
    required this.drafts,
    required this.tokens,
    this.onRemove,
  });

  final List<ChatDraftAttachment> drafts;
  final MaterialTokens tokens;
  final ValueChanged<int>? onRemove;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _size,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: drafts.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final draft = drafts[index];
                return SizedBox(
                  width: _size,
                  height: _size,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: _size,
                          height: _size,
                          decoration: BoxDecoration(
                            color: tokens.canvas,
                            border: Border.all(color: tokens.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.memory(
                            draft.bytes,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                                color: tokens.inkMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onRemove != null)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Semantics(
                            button: true,
                            label: '移除附图 ${index + 1}',
                            child: Material(
                              color: const Color(0xB8141413),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => onRemove!(index),
                                child: const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '已附加 ${drafts.length}/$maxChatAttachments 张 · 可空文发送',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Opacity(
          opacity: 0.35 + 0.65 * (1 - t),
          child: Transform.scale(
            scale: 0.85 + 0.15 * (1 - t),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
