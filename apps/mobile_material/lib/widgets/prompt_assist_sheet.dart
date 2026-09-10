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

    final draft = _workingPrompt.trim();
    if (draft.isEmpty) {
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
        _previewTab = 1;
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56, maxHeight: 120),
          child: SingleChildScrollView(
            child: Text(
              body,
              style: TextStyle(
                fontSize: 12,
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
        : (hasWorking ? _workingPrompt : '从下方选模板，或点「随机一条」');
    final previewEmpty = showingPolish ? polishEmpty : !hasWorking;

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
        const SizedBox(height: 8),
        _previewCard(
          tokens: tokens,
          body: previewBody,
          empty: previewEmpty && !_enhancing,
        ),
        const SizedBox(height: 12),
        if (!showingPolish)
          Row(
            children: [
              OutlinedButton(
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
                child: const Text('随机一条'),
              ),
              const SizedBox(width: 8),
              if (canEnhance)
                FilledButton.tonal(
                  onPressed: (!hasWorking && !_enhancing) ? null : _runEnhance,
                  style: kPromptToolRowBtnStyle,
                  child: Text(_enhancing ? '取消' : 'AI 润色'),
                ),
            ],
          )
        else
          Row(
            children: [
              if (_enhancing)
                FilledButton.tonal(
                  onPressed: _runEnhance,
                  style: kPromptToolRowBtnStyle,
                  child: const Text('取消'),
                ),
              const Spacer(),
              if (!_enhancing)
                FilledButton(
                  onPressed: polishEmpty
                      ? null
                      : () => widget.onApply(_enhancedPreview!),
                  style: kPromptToolRowBtnStyle,
                  child: const Text('应用润色结果'),
                ),
            ],
          ),
        if (_enhancing) ...[
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        FilledButton(
          onPressed: !hasWorking || _enhancing
              ? null
              : () => widget.onApply(_workingPrompt),
          child: const Text('填入提示词'),
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
    // 默认贴底固定约 88% 屏高；键盘弹出时缩短，避免顶出屏幕。
    final targetH = media.size.height * 0.88;
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
                          fontSize: 16,
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
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('模板')),
                    ButtonSegment(value: 1, label: Text('结构化')),
                  ],
                  selected: {_tabIndex},
                  onSelectionChanged: (set) {
                    if (set.isEmpty) return;
                    setState(() => _tabIndex = set.first);
                  },
                ),
                const SizedBox(height: 12),
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
