import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;

/// 结构化提示拼装面板：维度 Chip + 预览 + 填入/清空/AI 润色。
///
/// 提示词维度构建面板；S4 对 preview 调用 [enhancePrompt]。
class PromptBuilderPanel extends StatefulWidget {
  const PromptBuilderPanel({
    super.key,
    required this.domain,
    required this.onApply,
    this.mode,
    this.disabled = false,
    this.compact = false,
    this.providerRepository,
    this.chatDefaultsRepository,
    this.chatClient,
  });

  final PromptDomain domain;
  final ValueChanged<String> onApply;
  final String? mode;
  final bool disabled;
  final bool compact;
  final ProviderRepository? providerRepository;
  final ChatDefaultsRepository? chatDefaultsRepository;
  final OpenAiCompatibleChatClient? chatClient;

  @override
  State<PromptBuilderPanel> createState() => _PromptBuilderPanelState();
}

class _PromptBuilderPanelState extends State<PromptBuilderPanel> {
  late PromptBuilderState _state;
  bool _enhancing = false;
  String? _enhanceError;
  String? _enhancedPreview;
  http.Client? _enhanceHttp;

  @override
  void initState() {
    super.initState();
    _state = PromptBuilderState(widget.domain);
  }

  @override
  void didUpdateWidget(covariant PromptBuilderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.domain != widget.domain) {
      _state = PromptBuilderState(widget.domain);
      _enhanceError = null;
      _enhancedPreview = null;
    }
  }

  @override
  void dispose() {
    _enhanceHttp?.close();
    super.dispose();
  }

  bool get _hasPreview => _state.preview.trim().isNotEmpty;

  bool get _canEnhance => widget.providerRepository != null;

  bool _isSelected(String groupId, String optionId) {
    final val = _state.selection[groupId];
    if (val is List) return val.map((e) => e.toString()).contains(optionId);
    return val == optionId;
  }

  void _onChipTap(String groupId, String optionId) {
    if (widget.disabled || _enhancing) return;
    setState(() {
      _state.toggleOption(groupId, optionId);
      _enhanceError = null;
      _enhancedPreview = null;
    });
  }

  void _onApply() {
    if (widget.disabled || !_hasPreview || _enhancing) return;
    widget.onApply(_state.preview);
  }

  void _onClear() {
    if (widget.disabled || _enhancing) return;
    setState(() {
      _state.clear();
      _enhanceError = null;
      _enhancedPreview = null;
    });
  }

  Future<void> _runEnhance() async {
    if (_enhancing) {
      _enhanceHttp?.close();
      _enhanceHttp = null;
      setState(() {
        _enhancing = false;
        _enhanceError = '已取消';
      });
      return;
    }

    final draft = _state.preview.trim();
    if (draft.isEmpty) {
      setState(() {
        _enhanceError = '请先选择标签生成草稿';
        _enhancedPreview = null;
      });
      return;
    }

    final providers = widget.providerRepository;
    final creds = providers?.activeChatCredentials;
    if (providers == null || creds == null) {
      setState(() {
        _enhanceError = '请先在设置中配置对话模型与 API Key';
        _enhancedPreview = null;
      });
      return;
    }

    final defaults =
        widget.chatDefaultsRepository?.defaults ?? ChatDefaults.recommended;
    final client = widget.chatClient ?? OpenAiCompatibleChatClient();
    final ownedHttp = http.Client();
    _enhanceHttp = ownedHttp;

    setState(() {
      _enhancing = true;
      _enhanceError = null;
      _enhancedPreview = null;
    });

    try {
      final result = await enhancePrompt(
        text: draft,
        domain: widget.domain,
        mode: widget.mode,
        credentials: creds,
        chatClient: client,
        temperature: defaults.temperature,
        timeout: defaults.apiTimeout,
        client: ownedHttp,
      );
      if (!mounted) return;
      setState(() {
        _enhancedPreview = result;
        _enhancing = false;
        _enhanceError = null;
      });
    } on ChatAbortException {
      if (!mounted) return;
      setState(() {
        _enhancing = false;
        _enhanceError = '已取消';
      });
    } catch (e) {
      if (!mounted) return;
      if (isAbortLike(e)) {
        setState(() {
          _enhancing = false;
          _enhanceError = '已取消';
        });
        return;
      }
      final msg = e is ChatApiException
          ? e.message
          : sanitizeErrorText(e.toString(), '优化失败，请稍后重试');
      setState(() {
        _enhancing = false;
        _enhanceError = msg.isEmpty ? '优化失败，请稍后重试' : msg;
      });
    } finally {
      if (_enhanceHttp == ownedHttp) {
        ownedHttp.close();
        _enhanceHttp = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    // 与 PromptAssist「模板」Tab 同一套间距/卡片/按钮层级。
    const gap = 12.0;
    const groupGap = 8.0;
    const chipGap = 8.0;
    const chipPadH = 10.0;
    const chipPadV = 6.0;
    const chipFont = 12.0;

    final chipBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _state.dimensions.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          _buildGroup(
            tokens,
            _state.dimensions[i],
            groupGap: groupGap,
            chipGap: chipGap,
            chipPadH: chipPadH,
            chipPadV: chipPadV,
            chipFont: chipFont,
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AssistInfoCard(
          tokens: tokens,
          title: '当前草稿',
          child: Text(
            _hasPreview ? _state.preview : '选择下方标签生成草稿',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: _hasPreview ? tokens.inkSecondary : tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
        const SizedBox(height: gap),
        Row(
          children: [
            Button(
              onPressed: widget.disabled || _enhancing ? null : _onClear,
              child: const Text('清空'),
            ),
            const SizedBox(width: 8),
            if (_canEnhance)
              _EnhanceButton(
                tokens: tokens,
                enhancing: _enhancing,
                enabled: !widget.disabled && (_hasPreview || _enhancing),
                emptyHint: !_hasPreview && !_enhancing,
                onPressed: _runEnhance,
              ),
            const Spacer(),
            FilledButton(
              onPressed:
                  widget.disabled || !_hasPreview || _enhancing ? null : _onApply,
              child: const Text('填入'),
            ),
          ],
        ),
        if (_enhancing) ...[
          const SizedBox(height: 10),
          const ProgressBar(),
          const SizedBox(height: 4),
          Text(
            '正在用对话模型润色…',
            style: TextStyle(
              fontSize: 11,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
        if (_enhanceError != null && _enhanceError!.isNotEmpty) ...[
          const SizedBox(height: 10),
          InfoBar(
            title: Text(_enhanceError!),
            severity: _enhanceError == '已取消'
                ? InfoBarSeverity.info
                : InfoBarSeverity.error,
          ),
        ],
        if (_enhancedPreview != null) ...[
          const SizedBox(height: 10),
          _AssistInfoCard(
            tokens: tokens,
            title: '润色预览',
            trailing: FilledButton(
              onPressed: widget.disabled
                  ? null
                  : () => widget.onApply(_enhancedPreview!),
              child: const Text('应用润色结果'),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 110),
              child: SingleChildScrollView(
                child: Text(
                  _enhancedPreview!,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: gap),
        Expanded(
          child: SingleChildScrollView(child: chipBody),
        ),
      ],
    );
  }

  Widget _buildGroup(
    FluentTokens tokens,
    PromptDimensionGroup group, {
    required double groupGap,
    required double chipGap,
    required double chipPadH,
    required double chipPadV,
    required double chipFont,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            group.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          SizedBox(height: groupGap),
          Wrap(
            spacing: chipGap,
            runSpacing: chipGap,
            children: [
              for (final opt in group.options)
                _Chip(
                  label: opt.label,
                  active: _isSelected(group.id, opt.id),
                  enabled: !widget.disabled && !_enhancing,
                  padH: chipPadH,
                  padV: chipPadV,
                  fontSize: chipFont,
                  tokens: tokens,
                  onTap: () => _onChipTap(group.id, opt.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssistInfoCard extends StatelessWidget {
  const _AssistInfoCard({
    required this.tokens,
    required this.title,
    required this.child,
    this.trailing,
  });

  final FluentTokens tokens;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _EnhanceButton extends StatelessWidget {
  const _EnhanceButton({
    required this.tokens,
    required this.enhancing,
    required this.enabled,
    required this.emptyHint,
    required this.onPressed,
  });

  final FluentTokens tokens;
  final bool enhancing;
  final bool enabled;
  final bool emptyHint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Button(
      onPressed: enabled ? onPressed : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.isDisabled) {
            return tokens.surfaceMuted;
          }
          if (states.isPressed) {
            return tokens.primary.withValues(alpha: 0.22);
          }
          if (states.isHovered) {
            return tokens.primary.withValues(alpha: 0.16);
          }
          return tokens.primary.withValues(alpha: 0.12);
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.isDisabled) return tokens.inkMuted;
          return tokens.primaryPressed;
        }),
        shape: WidgetStateProperty.resolveWith((states) {
          final side = BorderSide(
            color: states.isDisabled
                ? tokens.border
                : tokens.primary.withValues(alpha: 0.35),
          );
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: side,
          );
        }),
      ),
      child: Text(
        enhancing ? '取消润色' : '✨ AI 润色',
        style: TextStyle(
          fontSize: 12,
          fontFamily: tokens.fontFamily,
        ),
      ),
    );
    if (!emptyHint) return button;
    return Tooltip(
      message: '请先选择标签生成草稿',
      child: button,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.enabled,
    required this.padH,
    required this.padV,
    required this.fontSize,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final double padH;
  final double padV;
  final double fontSize;
  final FluentTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: enabled ? onTap : null,
      builder: (context, states) {
        final hovered = states.isHovered || states.isPressed;
        final Color bg;
        final Color border;
        final Color fg;
        if (!enabled) {
          bg = tokens.surface;
          border = tokens.border;
          fg = tokens.inkMuted;
        } else if (active) {
          bg = tokens.primary.withValues(alpha: 0.08);
          border = tokens.primary;
          fg = tokens.primaryPressed;
        } else if (hovered) {
          bg = tokens.primary.withValues(alpha: 0.05);
          border = tokens.border;
          fg = tokens.inkSecondary;
        } else {
          bg = tokens.surface;
          border = tokens.border;
          fg = tokens.inkSecondary;
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: fg,
              fontFamily: tokens.fontFamily,
            ),
          ),
        );
      },
    );
  }
}
