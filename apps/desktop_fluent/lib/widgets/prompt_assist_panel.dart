import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:http/http.dart' as http;

import 'prompt_builder_panel.dart';

/// F-PromptAssist：模板选句 + 结构化拼装，均可 AI 润色后填入。
Future<void> showFluentPromptAssist(
  BuildContext context, {
  required PromptDomain domain,
  String? mode,
  required ValueChanged<String> onApply,
  String draftPrompt = '',
  ProviderRepository? providerRepository,
  ChatDefaultsRepository? chatDefaultsRepository,
  OpenAiCompatibleChatClient? chatClient,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return ContentDialog(
        title: Row(
          children: [
            const Expanded(child: Text('提示词辅助')),
            Tooltip(
              message: '关闭',
              child: Semantics(
                button: true,
                label: '关闭',
                excludeSemantics: true,
                child: IconButton(
                  icon: const Icon(FluentIcons.chrome_close, size: 12),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
        // OD dialog ~680×780，ContentDialog 约束放宽到接近 maxHeight 860。
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 860),
        content: PromptAssistPanel(
          domain: domain,
          mode: mode,
          draftPrompt: draftPrompt,
          providerRepository: providerRepository,
          chatDefaultsRepository: chatDefaultsRepository,
          chatClient: chatClient,
          onApply: (text) {
            onApply(text);
            Navigator.of(ctx).pop();
          },
        ),
      );
    },
  );
}

class PromptAssistPanel extends StatefulWidget {
  const PromptAssistPanel({
    super.key,
    required this.domain,
    this.mode,
    required this.onApply,
    this.draftPrompt = '',
    this.providerRepository,
    this.chatDefaultsRepository,
    this.chatClient,
  });

  final PromptDomain domain;
  final String? mode;
  final ValueChanged<String> onApply;
  final String draftPrompt;
  final ProviderRepository? providerRepository;
  final ChatDefaultsRepository? chatDefaultsRepository;
  final OpenAiCompatibleChatClient? chatClient;

  @override
  State<PromptAssistPanel> createState() => _PromptAssistPanelState();
}

class _PromptAssistPanelState extends State<PromptAssistPanel> {
  int _tabIndex = 0;
  bool _enhancing = false;
  String? _enhanceError;
  String? _enhancedPreview;
  http.Client? _enhanceHttp;
  late String _workingPrompt;
  late final TextEditingController _draftCtrl;
  String? _selectedPresetId;
  /// 模板上区预览局部切换：0=草稿，1=润色。
  int _previewTab = 0;
  String _enhanceSkillId = defaultPromptEnhanceSkill.id;

  static const _draftPlaceholder = '在此编辑草稿，或从模板 / 结构化拼出…';

  @override
  void initState() {
    super.initState();
    _workingPrompt = widget.draftPrompt;
    _draftCtrl = TextEditingController(text: widget.draftPrompt);
  }

  @override
  void dispose() {
    _enhanceHttp?.close();
    _draftCtrl.dispose();
    super.dispose();
  }

  void _clearEnhanceAndShowDraft() {
    _enhanceError = null;
    _enhancedPreview = null;
    _previewTab = 0;
  }

  void _selectPrompt(String text, {String? presetId}) {
    if (_enhancing) return;
    setState(() {
      _workingPrompt = text;
      _selectedPresetId = presetId;
      _clearEnhanceAndShowDraft();
    });
    _draftCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onDraftEdited(String value) {
    setState(() {
      _workingPrompt = value;
      _selectedPresetId = null;
      _enhancedPreview = null;
      _enhanceError = null;
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

    final draft = _workingPrompt.trim();
    final previous = _enhancedPreview?.trim();
    final useEnhancedAsBase = previous != null && previous.isNotEmpty;
    final sourceText = useEnhancedAsBase ? previous : draft;
    if (sourceText.isEmpty) {
      setState(() {
        _enhanceError = '请先选中模板或输入提示词再优化';
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

  Widget _buildSegmentedTab(FluentTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentTab(
              label: '模板',
              selected: _tabIndex == 0,
              tokens: tokens,
              onPressed: () => setState(() => _tabIndex = 0),
            ),
          ),
          Expanded(
            child: _SegmentTab(
              label: '结构化',
              selected: _tabIndex == 1,
              tokens: tokens,
              onPressed: () => setState(() => _tabIndex = 1),
            ),
          ),
        ],
      ),
    );
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
        // OD preview-text max-height ~96px。
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

  Widget _draftEditor(FluentTokens tokens) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 96),
      child: TextBox(
        controller: _draftCtrl,
        onChanged: _enhancing ? null : _onDraftEdited,
        enabled: !_enhancing,
        maxLines: null,
        minLines: 3,
        padding: const EdgeInsets.fromLTRB(10, 6, 18, 6),
        placeholder: _draftPlaceholder,
        placeholderStyle: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: tokens.inkMuted,
          fontFamily: tokens.fontFamily,
        ),
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: tokens.inkSecondary,
          fontFamily: tokens.fontFamily,
        ),
      ),
    );
  }

  ButtonStyle _enhanceBtnStyle(FluentTokens tokens) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.isDisabled) return tokens.surfaceMuted;
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
    );
  }

  Widget _buildTemplateToolRow({
    required FluentTokens tokens,
    required List<PromptPreset> presets,
    required bool canEnhance,
    required bool hasWorking,
    required bool polishEmpty,
  }) {
    final hasEnhanced = _enhancedPreview?.trim().isNotEmpty ?? false;
    return Row(
      children: [
        promptToolRowHeight(
          Button(
            onPressed: presets.isEmpty || _enhancing
                ? null
                : () {
                    final p = pickRandomPromptPreset(
                      widget.domain,
                      mode: widget.mode,
                    );
                    if (p != null) {
                      _selectPrompt(p.prompt, presetId: p.id);
                    }
                  },
            child: Text(
              '随机',
              style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
            ),
          ),
        ),
        const SizedBox(width: 8),
        promptToolRowHeight(
          Button(
            onPressed: !hasWorking || _enhancing
                ? null
                : () => widget.onApply(_workingPrompt),
            child: Text(
              '填入',
              style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
            ),
          ),
        ),
        const Spacer(),
        if (canEnhance)
          promptToolRowHeight(
            Button(
              onPressed: (!hasWorking && !hasEnhanced && !_enhancing)
                  ? null
                  : _runEnhance,
              style: _enhancing
                  ? ButtonStyle(
                      backgroundColor: WidgetStatePropertyAll(tokens.danger),
                      foregroundColor:
                          const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
                    )
                  : _enhanceBtnStyle(tokens),
              child: Text(
                _enhancing ? '取消' : '✨ AI 润色',
                style: TextStyle(fontSize: 12, fontFamily: tokens.fontFamily),
              ),
            ),
          ),
        if (canEnhance && !_enhancing) ...[
          const SizedBox(width: 8),
          promptToolRowHeight(
            FilledButton(
              onPressed: polishEmpty
                  ? null
                  : () => widget.onApply(_enhancedPreview!),
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

  Widget _buildTemplateTab(FluentTokens tokens) {
    final presets = getPromptPresets(widget.domain, mode: widget.mode);
    final canEnhance = widget.providerRepository != null;
    final hasWorking = _workingPrompt.trim().isNotEmpty;
    final showingPolish = _previewTab == 1;
    final polishEmpty = _enhancedPreview == null;
    final polishBody = polishEmpty
        ? (_enhancing ? '正在润色…' : '暂无润色结果，可先在「草稿」点 AI 润色')
        : _enhancedPreview!;

    // 上区非 flex（预览/风格/迭代）；模板列表 Expanded 吃剩余高度。
    return Column(
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
        if (showingPolish)
          _previewCard(
            tokens: tokens,
            body: polishBody,
            empty: polishEmpty && !_enhancing,
          )
        else
          _draftEditor(tokens),
        if (canEnhance) ...[
          const SizedBox(height: 8),
          PromptEnhanceSkillSelector(
            tokens: tokens,
            selectedId: _enhanceSkillId,
            enabled: !_enhancing,
            onSelected: (id) => setState(() => _enhanceSkillId = id),
          ),
        ],
        if (canEnhance &&
            (_enhancedPreview?.trim().isNotEmpty ?? false) &&
            !_enhancing) ...[
          const SizedBox(height: 8),
          PromptRefineChips(
            tokens: tokens,
            enabled: true,
            onRefine: _runRefine,
          ),
        ],
        if (_enhancing) ...[
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
          InfoBar(
            title: Text(_enhanceError!),
            severity: _enhanceError == '已取消'
                ? InfoBarSeverity.info
                : InfoBarSeverity.error,
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(right: 8),
            itemCount: presets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final p = presets[index];
              final selected = _selectedPresetId == p.id;
              return HoverButton(
                onPressed: _enhancing
                    ? null
                    : () => _selectPrompt(p.prompt, presetId: p.id),
                builder: (context, states) {
                  final hovered = states.isHovered || states.isPressed;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.primary.withValues(alpha: 0.08)
                          : hovered
                              ? tokens.primary.withValues(alpha: 0.05)
                              : tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? tokens.primary : tokens.border,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 36,
                          margin: const EdgeInsets.only(right: 10, top: 2),
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.primary
                                : tokens.border.withValues(alpha: 0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.ink,
                                  fontFamily: tokens.fontFamily,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.prompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: tokens.inkSecondary,
                                  fontFamily: tokens.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: tokens.border),
        const SizedBox(height: 10),
        _buildTemplateToolRow(
          tokens: tokens,
          presets: presets,
          canEnhance: canEnhance,
          hasWorking: hasWorking,
          polishEmpty: polishEmpty,
        ),
      ],
    );
  }

  Widget _buildStructuredTab() {
    return PromptBuilderPanel(
      domain: widget.domain,
      mode: widget.mode,
      onApply: widget.onApply,
      providerRepository: widget.providerRepository,
      chatDefaultsRepository: widget.chatDefaultsRepository,
      chatClient: widget.chatClient,
      compact: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    // OD dialog ~680×780；内容区加高，给模板列表更多视口。
    return SizedBox(
      width: 680,
      height: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '选模板或拼标签，可润色后填入',
            style: TextStyle(
              fontSize: 12,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          const SizedBox(height: 10),
          _buildSegmentedTab(tokens),
          const SizedBox(height: 10),
          Expanded(
            child: _tabIndex == 0
                ? _buildTemplateTab(tokens)
                : _buildStructuredTab(),
          ),
        ],
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
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
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? tokens.surface : const Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? tokens.primary.withValues(alpha: 0.45)
                  : tokens.border.withValues(alpha: 0),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: tokens.ink.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
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
