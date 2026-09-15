import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 工具行按钮统一高度（与 FilledButton.tonal「AI 润色」默认 40 对齐）。
const ButtonStyle kPromptToolRowBtnStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 40)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

/// M-PromptBuilder：结构化提示拼装面板（Chip + 预览 + 填入/清空/AI 润色）。
///
/// 由「提示词辅助」Sheet 的「结构化」分段嵌入复用。
class PromptBuilderPanel extends StatefulWidget {
  const PromptBuilderPanel({
    super.key,
    required this.domain,
    required this.onApply,
    this.mode,
    this.disabled = false,
    this.providerRepository,
    this.chatDefaultsRepository,
    this.chatClient,
  });

  final PromptDomain domain;
  final ValueChanged<String> onApply;
  final String? mode;
  final bool disabled;
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
    required MaterialTokens tokens,
    required String body,
    required bool empty,
  }) {
    return Material(
      color: tokens.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              body,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: empty ? tokens.inkMuted : tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolRow({
    required bool polishEmpty,
  }) {
    final hasEnhanced = _enhancedPreview?.trim().isNotEmpty ?? false;
    final enhanceBtn = FilledButton.tonal(
      onPressed: widget.disabled ||
              (!_hasPreview && !hasEnhanced && !_enhancing)
          ? null
          : _runEnhance,
      style: kPromptToolRowBtnStyle,
      child: Text(_enhancing ? '取消' : '✨ AI 润色'),
    );

    return Row(
      children: [
        TextButton(
          onPressed: widget.disabled || _enhancing ? null : _onClear,
          style: kPromptToolRowBtnStyle,
          child: const Text('清空'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed:
              widget.disabled || !_hasPreview || _enhancing ? null : _onApplyDraft,
          style: kPromptToolRowBtnStyle,
          child: const Text('填入'),
        ),
        const Spacer(),
        if (_canEnhance)
          (!_hasPreview && !hasEnhanced && !_enhancing)
              ? Tooltip(message: '请先选择标签生成草稿', child: enhanceBtn)
              : enhanceBtn,
        if (_canEnhance && !_enhancing) ...[
          const SizedBox(width: 8),
          FilledButton(
            onPressed: widget.disabled || polishEmpty ? null : _onApplyEnhanced,
            style: kPromptToolRowBtnStyle,
            child: const Text('应用润色'),
          ),
        ],
      ],
    );
  }

  Widget _buildTopSection(MaterialTokens tokens) {
    const gap = 8.0;
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
          child: DraftPolishUnderlineToggle(
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
          const SizedBox(height: gap),
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
          const SizedBox(height: gap),
          PromptRefineChips(
            tokens: tokens,
            enabled: !widget.disabled,
            onRefine: _runRefine,
          ),
        ],
        if (_enhancing) ...[
          const SizedBox(height: gap),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text(
            '正在用对话模型润色…',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ],
        if (_enhanceError != null && _enhanceError!.isNotEmpty) ...[
          const SizedBox(height: gap),
          Material(
            color: _enhanceError == '已取消'
                ? tokens.surfaceMuted
                : tokens.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Text(
                _enhanceError!,
                style: TextStyle(
                  fontSize: 12,
                  color: _enhanceError == '已取消'
                      ? tokens.inkMuted
                      : tokens.danger,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    const gap = 8.0;
    final polishEmpty = _enhancedPreview == null;

    // 上区非 flex；结构化 chips Expanded 吃剩余高度；底栏一行工具。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopSection(tokens),
        const SizedBox(height: gap),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _state.dimensions.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  _buildGroup(tokens, _state.dimensions[i]),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: gap),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildToolRow(polishEmpty: polishEmpty),
          ),
        ),
      ],
    );
  }

  Widget _buildGroup(MaterialTokens tokens, PromptDimensionGroup group) {
    return Material(
      color: tokens.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opt in group.options)
                  FilterChip(
                    label: Text(opt.label),
                    selected: _isSelected(group.id, opt.id),
                    showCheckmark: false,
                    onSelected: widget.disabled || _enhancing
                        ? null
                        : (_) => _onChipTap(group.id, opt.id),
                    visualDensity: VisualDensity.standard,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    labelStyle: TextStyle(
                      fontSize: 13,
                      fontFamily: tokens.fontFamily,
                      color: _isSelected(group.id, opt.id)
                          ? tokens.primary
                          : tokens.inkSecondary,
                    ),
                    selectedColor: tokens.primary.withValues(alpha: 0.14),
                    side: BorderSide(
                      color: _isSelected(group.id, opt.id)
                          ? tokens.primary
                          : tokens.border,
                    ),
                    backgroundColor: tokens.surface,
                  ),
              ],
            ),
          ],
        ),
      ),
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

  final MaterialTokens tokens;
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
              for (final tip in kPromptRefineInstructions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(tip),
                    selected: false,
                    showCheckmark: false,
                    onSelected: enabled ? (_) => onRefine(tip) : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: tokens.fontFamily,
                      color: tokens.inkSecondary,
                    ),
                    side: BorderSide(color: tokens.border),
                    backgroundColor: tokens.surface,
                  ),
                ),
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

  final MaterialTokens tokens;
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
              for (final skill in promptEnhanceSkills) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(skill.label),
                    selected: selectedId == skill.id,
                    showCheckmark: false,
                    onSelected: enabled
                        ? (_) => onSelected(skill.id)
                        : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: tokens.fontFamily,
                      color: selectedId == skill.id
                          ? tokens.primary
                          : tokens.inkSecondary,
                    ),
                    selectedColor: tokens.primary.withValues(alpha: 0.14),
                    side: BorderSide(
                      color: selectedId == skill.id
                          ? tokens.primary
                          : tokens.border,
                    ),
                    backgroundColor: tokens.surface,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 上区内「草稿 | 润色」下划线 Tab，比外层「模板|结构化」更轻。
class DraftPolishUnderlineToggle extends StatelessWidget {
  const DraftPolishUnderlineToggle({
    super.key,
    required this.tokens,
    required this.selected,
    required this.onChanged,
  });

  final MaterialTokens tokens;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DraftPolishUnderlineItem(
          label: '草稿',
          selected: selected == 0,
          tokens: tokens,
          onTap: () => onChanged(0),
        ),
        _DraftPolishUnderlineItem(
          label: '润色',
          selected: selected == 1,
          tokens: tokens,
          onTap: () => onChanged(1),
        ),
      ],
    );
  }
}

class _DraftPolishUnderlineItem extends StatelessWidget {
  const _DraftPolishUnderlineItem({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final MaterialTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: MaterialMotion.micro,
        curve: MaterialMotion.standard,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
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
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? tokens.primary : tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ),
    );
  }
}
