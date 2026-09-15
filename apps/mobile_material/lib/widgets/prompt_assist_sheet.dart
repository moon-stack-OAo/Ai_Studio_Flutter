import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'prompt_builder_panel.dart';

/// M-PromptAssist：模板选句 + 结构化拼装，均可 AI 润色后填入。
Future<void> showMaterialPromptAssist(
  BuildContext context, {
  required PromptDomain domain,
  String? mode,
  required ValueChanged<String> onApply,
  String draftPrompt = '',
  ProviderRepository? providerRepository,
  ChatDefaultsRepository? chatDefaultsRepository,
  OpenAiCompatibleChatClient? chatClient,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return PromptAssistSheet(
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
      );
    },
  );
}

class PromptAssistSheet extends StatefulWidget {
  const PromptAssistSheet({
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
  State<PromptAssistSheet> createState() => _PromptAssistSheetState();
}

class _PromptAssistSheetState extends State<PromptAssistSheet> {
  int _tabIndex = 0;
  bool _enhancing = false;
  String? _enhanceError;
  String? _enhancedPreview;
  http.Client? _enhanceHttp;
  late String _workingPrompt;
  String? _selectedPresetId;
  /// 模板上区预览局部切换：0=草稿，1=润色。
  int _previewTab = 0;
  String _enhanceSkillId = defaultPromptEnhanceSkill.id;

  @override
  void initState() {
    super.initState();
    _workingPrompt = widget.draftPrompt;
  }

  @override
  void dispose() {
    _enhanceHttp?.close();
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
          // OD ~72px；触控略放宽，避免再挤没模板列表。
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 88),
          child: SingleChildScrollView(
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

  /// 外层「模板 | 结构化」无边框下划线 Tab（对齐 OD `.outer-seg`）。
  Widget _buildOuterUnderlineTab(MaterialTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _OuterUnderlineTabItem(
              label: '模板',
              selected: _tabIndex == 0,
              tokens: tokens,
              onTap: () => setState(() => _tabIndex = 0),
            ),
          ),
          Expanded(
            child: _OuterUnderlineTabItem(
              label: '结构化',
              selected: _tabIndex == 1,
              tokens: tokens,
              onTap: () => setState(() => _tabIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateToolRow({
    required List<PromptPreset> presets,
    required bool canEnhance,
    required bool hasWorking,
    required bool polishEmpty,
  }) {
    final hasEnhanced = _enhancedPreview?.trim().isNotEmpty ?? false;
    return Row(
      children: [
        TextButton(
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
          style: kPromptToolRowBtnStyle,
          child: const Text('随机'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: !hasWorking || _enhancing
              ? null
              : () => widget.onApply(_workingPrompt),
          style: kPromptToolRowBtnStyle,
          child: const Text('填入'),
        ),
        const Spacer(),
        if (canEnhance)
          FilledButton.tonal(
            onPressed: (!hasWorking && !hasEnhanced && !_enhancing)
                ? null
                : _runEnhance,
            style: kPromptToolRowBtnStyle,
            child: Text(_enhancing ? '取消' : 'AI 润色'),
          ),
        if (canEnhance && !_enhancing) ...[
          const SizedBox(width: 8),
          FilledButton(
            onPressed: polishEmpty
                ? null
                : () => widget.onApply(_enhancedPreview!),
            style: kPromptToolRowBtnStyle,
            child: const Text('应用润色'),
          ),
        ],
      ],
    );
  }

  Widget _buildTemplateTab(MaterialTokens tokens) {
    final presets = getPromptPresets(widget.domain, mode: widget.mode);
    final canEnhance = widget.providerRepository != null;
    final hasWorking = _workingPrompt.trim().isNotEmpty;
    final showingPolish = _previewTab == 1;
    final polishEmpty = _enhancedPreview == null;
    final previewBody = showingPolish
        ? (polishEmpty
            ? (_enhancing ? '正在润色…' : '暂无润色结果，可先在「草稿」点 AI 润色')
            : _enhancedPreview!)
        : (hasWorking ? _workingPrompt : '从下方选模板，或点「随机」');
    final previewEmpty = showingPolish ? polishEmpty : !hasWorking;

    // 上区非 flex；模板 ListView Expanded 吃剩余高度（对齐 OD tpl-list）。
    return Column(
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
          const SizedBox(height: 8),
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
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: presets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = presets[index];
              final selected = _selectedPresetId == p.id;
              return Material(
                color: selected
                    ? tokens.primary.withValues(alpha: 0.14)
                    : tokens.surfaceMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selected ? tokens.primary : tokens.border,
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _enhancing
                      ? null
                      : () => _selectPrompt(p.prompt, presetId: p.id),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 14,
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
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildTemplateToolRow(
              presets: presets,
              canEnhance: canEnhance,
              hasWorking: hasWorking,
              polishEmpty: polishEmpty,
            ),
          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // OD sheet 约 92%；键盘弹出时缩短，避免顶出屏幕。
    final targetH = media.size.height * 0.90;
    final sheetH = keyboard > 0
        ? (media.size.height - keyboard).clamp(0.0, targetH)
        : targetH;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: sheetH,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '提示词辅助',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                Text(
                  '选模板或拼标签，可润色后填入',
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                _buildOuterUnderlineTab(tokens),
                const SizedBox(height: 8),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: [
                      _buildTemplateTab(tokens),
                      _buildStructuredTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OuterUnderlineTabItem extends StatelessWidget {
  const _OuterUnderlineTabItem({
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
      child: AnimatedContainer(
        duration: MaterialMotion.micro,
        curve: MaterialMotion.standard,
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 44),
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
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? tokens.primaryPressed : tokens.inkMuted,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ),
    );
  }
}
