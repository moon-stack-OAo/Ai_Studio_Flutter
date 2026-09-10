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
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
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
    );
  }

  Widget _buildTemplateTab(FluentTokens tokens) {
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
          child: _DraftPolishToggle(
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
                    '随机一条',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (canEnhance)
                promptToolRowHeight(
                  Button(
                    onPressed:
                        (!hasWorking && !_enhancing) ? null : _runEnhance,
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
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
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
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
                      _enhancing ? '取消' : '✨ AI 润色',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              promptToolRowHeight(
                FilledButton(
                  onPressed: !hasWorking || _enhancing
                      ? null
                      : () => widget.onApply(_workingPrompt),
                  child: Text(
                    '填入',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              if (_enhancing)
                promptToolRowHeight(
                  Button(
                    onPressed: _runEnhance,
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
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
                      foregroundColor:
                          WidgetStateProperty.resolveWith((states) {
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
                      '取消',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (!_enhancing)
                promptToolRowHeight(
                  FilledButton(
                    onPressed: polishEmpty
                        ? null
                        : () => widget.onApply(_enhancedPreview!),
                    child: Text(
                      '应用润色结果',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
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
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: presets.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
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
    return SizedBox(
      width: 700,
      height: 600,
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
          const SizedBox(height: 12),
          _buildSegmentedTab(tokens),
          const SizedBox(height: 12),
          Container(height: 1, color: tokens.border),
          const SizedBox(height: 12),
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
          duration: const Duration(milliseconds: 120),
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
          duration: const Duration(milliseconds: 100),
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
