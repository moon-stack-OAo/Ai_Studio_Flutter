import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  Widget _infoCard({
    required MaterialTokens tokens,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    const gap = 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoCard(
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
            OutlinedButton(
              onPressed: widget.disabled || _enhancing ? null : _onClear,
              child: const Text('清空'),
            ),
            const SizedBox(width: 8),
            if (_canEnhance)
              Builder(
                builder: (context) {
                  final btn = FilledButton.tonal(
                    onPressed: widget.disabled ||
                            (!_hasPreview && !_enhancing)
                        ? null
                        : _runEnhance,
                    child: Text(_enhancing ? '取消' : 'AI 润色'),
                  );
                  if (!_hasPreview && !_enhancing) {
                    return Tooltip(
                      message: '请先选择标签生成草稿',
                      child: btn,
                    );
                  }
                  return btn;
                },
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
        if (_enhancedPreview != null) ...[
          const SizedBox(height: 10),
          _infoCard(
            tokens: tokens,
            title: '润色预览',
            trailing: FilledButton(
              onPressed: widget.disabled
                  ? null
                  : () => widget.onApply(_enhancedPreview!),
              child: const Text('用润色结果'),
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
          child: SingleChildScrollView(
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
        FilledButton(
          onPressed:
              widget.disabled || !_hasPreview || _enhancing ? null : _onApply,
          child: const Text('填入提示词'),
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
