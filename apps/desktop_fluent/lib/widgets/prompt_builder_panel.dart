import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;

/// 工具行按钮统一高度（对齐 AI 润色，罩住 fontSize12 + padding + emoji）。
const double kPromptToolRowBtnHeight = 32;

Widget promptToolRowHeight(Widget child) =>
    SizedBox(height: kPromptToolRowBtnHeight, child: child);

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
  /// 上区预览局部切换：0=草稿，1=润色。
  int _previewTab = 0;
  String _enhanceSkillId = defaultPromptEnhanceSkill.id;

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
      _previewTab = 0;
    }
  }

  @override
  void dispose() {
    _enhanceHttp?.close();
    super.dispose();
  }

  bool get _hasPreview => _state.preview.trim().isNotEmpty;

  bool get _canEnhance => widget.providerRepository != null;

  bool get _showingPolish => _previewTab == 1;

  void _clearEnhanceAndShowDraft() {
    _enhanceError = null;
    _enhancedPreview = null;
    _previewTab = 0;
  }

  bool _isSelected(String groupId, String optionId) {
    final val = _state.selection[groupId];
    if (val is List) return val.map((e) => e.toString()).contains(optionId);
    return val == optionId;
  }

  void _onChipTap(String groupId, String optionId) {
    if (widget.disabled || _enhancing) return;
    setState(() {
      _state.toggleOption(groupId, optionId);
      _clearEnhanceAndShowDraft();
    });
  }

  void _onApplyDraft() {
    if (widget.disabled || !_hasPreview || _enhancing) return;
    widget.onApply(_state.preview);
  }

  void _onApplyEnhanced() {
    final text = _enhancedPreview;
    if (widget.disabled || text == null || text.trim().isEmpty) return;
    widget.onApply(text);
  }

  void _onClear() {
    if (widget.disabled || _enhancing) return;
    setState(() {
      _state.clear();
      _clearEnhanceAndShowDraft();
    });
  }

  Future<void> _cancelEnhance() async {
    _enhanceHttp?.close();
    _enhanceHttp = null;
    setState(() {
      _enhancing = false;
      _enhancedPreview = null;
      _enhanceError = '已取消';
    });
  }

  Future<void> _runEnhance() async {
    if (_enhancing) {
      await _cancelEnhance();
      return;
    }

    final draft = _state.preview.trim();
    final previous = _enhancedPreview?.trim();
    final useEnhancedAsBase = previous != null && previous.isNotEmpty;
    final sourceText = useEnhancedAsBase ? previous : draft;
    if (sourceText.isEmpty) {
      setState(() {
        _enhanceError = '请先选择标签生成草稿';
        _enhancedPreview = null;
        _previewTab = 0;
      });
      return;
    }

    final providers = widget.providerRepository;
    final creds = providers?.activeChatCredentials;
    if (providers == null || creds == null) {
      setState(() {
        _enhanceError = '请先在设置中配置对话模型与 API Key';
        _enhancedPreview = null;
        _previewTab = 0;
      });
      return;
    }

    final defaults =
        widget.chatDefaultsRepository?.defaults ?? ChatDefaults.recommended;
    final client = widget.chatClient ?? OpenAiCompatibleChatClient();
    final ownedHttp = createSafeHttpClient();
    _enhanceHttp = ownedHttp;

    setState(() {
      _enhancing = true;
      _enhanceError = null;
      _enhancedPreview = null;
      _previewTab = 1;
    });

    try {
      final result = await enhancePrompt(
        text: sourceText,
        domain: widget.domain,
        mode: widget.mode,
        skillId: _enhanceSkillId,
        credentials: creds,
        chatClient: client,
        timeout: defaults.apiTimeout,
        client: ownedHttp,
        onDelta: (delta, full) {
          if (!mounted || !_enhancing) return;
          setState(() => _enhancedPreview = full);
        },
      );
      if (!mounted) return;
      setState(() {
        _enhancedPreview = result;
        _enhancing = false;
        _enhanceError = null;
        _previewTab = 1;
      });
    } on ChatAbortException {
      if (!mounted) return;
      setState(() {
        _enhancing = false;
        _enhancedPreview = null;
        _enhanceError = '已取消';
      });
    } catch (e) {
      if (!mounted) return;
      if (isAbortLike(e)) {
        setState(() {
          _enhancing = false;
          _enhancedPreview = null;
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

  Future<void> _runRefine(String instruction) async {
    if (_enhancing) return;

    final previous = _enhancedPreview?.trim();
    if (previous == null || previous.isEmpty) {
      setState(() {
        _enhanceError = '请先完成一次润色再继续修改';
        _previewTab = 1;
      });
      return;
    }

    final providers = widget.providerRepository;
    final creds = providers?.activeChatCredentials;
    if (providers == null || creds == null) {
      setState(() {
        _enhanceError = '请先在设置中配置对话模型与 API Key';
        _previewTab = 1;
      });
      return;
    }

    final defaults =
        widget.chatDefaultsRepository?.defaults ?? ChatDefaults.recommended;
    final client = widget.chatClient ?? OpenAiCompatibleChatClient();
    final ownedHttp = createSafeHttpClient();
    _enhanceHttp = ownedHttp;

    setState(() {
      _enhancing = true;
      _enhanceError = null;
      _enhancedPreview = null;
      _previewTab = 1;
    });

    try {
      final result = await refineEnhancedPrompt(
        previous: previous,
        instruction: instruction,
        domain: widget.domain,
        mode: widget.mode,
        skillId: _enhanceSkillId,
        credentials: creds,
        chatClient: client,
        timeout: defaults.apiTimeout,
        client: ownedHttp,
        onDelta: (delta, full) {
          if (!mounted || !_enhancing) return;
          setState(() => _enhancedPreview = full);
        },
      );
      if (!mounted) return;
      setState(() {
        _enhancedPreview = result;
        _enhancing = false;
        _enhanceError = null;
        _previewTab = 1;
      });
    } on ChatAbortException {
      if (!mounted) return;
      setState(() {
        _enhancing = false;
        _enhancedPreview = null;
        _enhanceError = '已取消';
      });
    } catch (e) {
      if (!mounted) return;
      if (isAbortLike(e)) {
        setState(() {
          _enhancing = false;
          _enhancedPreview = null;
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

  Widget _previewCard({
    required FluentTokens tokens,
    required String body,
    required bool empty,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 96),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            body,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: empty ? tokens.inkMuted : tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolRow({
    required FluentTokens tokens,
    required bool polishEmpty,
  }) {
    final hasEnhanced = _enhancedPreview?.trim().isNotEmpty ?? false;
    return Row(
      children: [
        promptToolRowHeight(
          Button(
            onPressed: widget.disabled || _enhancing ? null : _onClear,
            child: Text(
              '清空',
              style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
            ),
          ),
        ),
        const SizedBox(width: 8),
        promptToolRowHeight(
          Button(
            onPressed: widget.disabled || !_hasPreview || _enhancing
                ? null
                : _onApplyDraft,
            child: Text(
              '填入',
              style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
            ),
          ),
        ),
        const Spacer(),
        if (_canEnhance)
          _EnhanceButton(
            tokens: tokens,
            enhancing: _enhancing,
            enabled: !widget.disabled &&
                (_hasPreview || hasEnhanced || _enhancing),
            emptyHint: !_hasPreview && !hasEnhanced && !_enhancing,
            onPressed: _runEnhance,
          ),
        if (_canEnhance && !_enhancing) ...[
          const SizedBox(width: 8),
          promptToolRowHeight(
            FilledButton(
              onPressed:
                  widget.disabled || polishEmpty ? null : _onApplyEnhanced,
              child: Text(
                '应用润色',
                style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopSection(FluentTokens tokens, double gap) {
    final polishEmpty = _enhancedPreview == null;
    final previewBody = _showingPolish
        ? (polishEmpty
            ? (_enhancing ? '正在润色…' : '暂无润色结果，可先在「草稿」点 AI 润色')
            : _enhancedPreview!)
        : (_hasPreview ? _state.preview : '选择下方标签生成草稿');
    final previewEmpty = _showingPolish ? polishEmpty : !_hasPreview;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _DraftPolishToggle(
            tokens: tokens,
            selected: _previewTab,
            onChanged: (v) => setState(() => _previewTab = v),
          ),
        ),
        const SizedBox(height: 6),
        _previewCard(
          tokens: tokens,
          body: previewBody,
          empty: previewEmpty && !_enhancing,
        ),
        if (_canEnhance) ...[
          SizedBox(height: gap),
          PromptEnhanceSkillSelector(
            tokens: tokens,
            selectedId: _enhanceSkillId,
            enabled: !widget.disabled && !_enhancing,
            onSelected: (id) => setState(() => _enhanceSkillId = id),
          ),
        ],
        if (_canEnhance &&
            (_enhancedPreview?.trim().isNotEmpty ?? false) &&
            !_enhancing) ...[
          SizedBox(height: gap),
          PromptRefineChips(
            tokens: tokens,
            enabled: !widget.disabled,
            onRefine: _runRefine,
          ),
        ],
        if (_enhancing) ...[
          SizedBox(height: gap),
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
          SizedBox(height: gap),
          InfoBar(
            title: Text(_enhanceError!),
            severity: _enhanceError == '已取消'
                ? InfoBarSeverity.info
                : InfoBarSeverity.error,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final gap = widget.compact ? 8.0 : 10.0;
    const groupGap = 8.0;
    const chipGap = 8.0;
    const chipPadH = 10.0;
    const chipPadV = 6.0;
    const chipFont = 12.0;
    final polishEmpty = _enhancedPreview == null;

    final chipBody = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _state.dimensions.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
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

    // 上区非 flex；chips Expanded 吃剩余高度；底栏一行工具。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopSection(tokens, gap),
        SizedBox(height: gap),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8),
            child: chipBody,
          ),
        ),
        SizedBox(height: gap),
        Container(height: 1, color: tokens.border),
        const SizedBox(height: 10),
        _buildToolRow(tokens: tokens, polishEmpty: polishEmpty),
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

/// 上区内「草稿 | 润色」下划线 Tab，不与外层「模板|结构化」同级抢视觉。
class _DraftPolishToggle extends StatelessWidget {
  const _DraftPolishToggle({
    required this.tokens,
    required this.selected,
    required this.onChanged,
  });

  final FluentTokens tokens;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DraftPolishToggleItem(
          label: '草稿',
          selected: selected == 0,
          tokens: tokens,
          onPressed: () => onChanged(0),
        ),
        _DraftPolishToggleItem(
          label: '润色',
          selected: selected == 1,
          tokens: tokens,
          onPressed: () => onChanged(1),
        ),
      ],
    );
  }
}

class _DraftPolishToggleItem extends StatelessWidget {
  const _DraftPolishToggleItem({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final FluentTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        return AnimatedContainer(
          duration: FluentMotion.micro,
          curve: FluentMotion.standard,
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? tokens.primary : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? tokens.primary : tokens.inkSecondary,
              fontFamily: tokens.fontFamily,
            ),
          ),
        );
      },
    );
  }
}

/// 快捷迭代指令（B2）；勿称 skill。
const List<String> kPromptRefineInstructions = [
  '再短一点',
  '更电影感',
  '少加点戏',
];

/// 有润色结果且非润色中时显示的快捷迭代 Chip。
class PromptRefineChips extends StatelessWidget {
  const PromptRefineChips({
    super.key,
    required this.tokens,
    required this.onRefine,
    this.enabled = true,
  });

  final FluentTokens tokens;
  final ValueChanged<String> onRefine;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '快捷迭代',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < kPromptRefineInstructions.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _SkillChip(
                  label: kPromptRefineInstructions[i],
                  active: false,
                  enabled: enabled,
                  tokens: tokens,
                  onTap: () => onRefine(kPromptRefineInstructions[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 润色风格横滑 Chip（文案用「润色风格」，不用「技能」）。
class PromptEnhanceSkillSelector extends StatelessWidget {
  const PromptEnhanceSkillSelector({
    super.key,
    required this.tokens,
    required this.selectedId,
    required this.onSelected,
    this.enabled = true,
  });

  final FluentTokens tokens;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '润色风格',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < promptEnhanceSkills.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _SkillChip(
                  label: promptEnhanceSkills[i].label,
                  active: selectedId == promptEnhanceSkills[i].id,
                  enabled: enabled,
                  tokens: tokens,
                  onTap: () => onSelected(promptEnhanceSkills[i].id),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.label,
    required this.active,
    required this.enabled,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
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
          duration: FluentMotion.micro,
          curve: FluentMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
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
    final button = promptToolRowHeight(
      Button(
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
          enhancing ? '取消' : '✨ AI 润色',
          style: TextStyle(
            fontSize: 12,
            fontFamily: tokens.fontFamily,
          ),
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
          duration: FluentMotion.micro,
          curve: FluentMotion.standard,
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
