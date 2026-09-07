import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// M-ImageParams + M-PromptBox + M-RefImage + M-GenPrimary。
class ImageComposer extends StatefulWidget {
  const ImageComposer({
    super.key,
    required this.prompt,
    required this.onPromptChanged,
    required this.n,
    required this.onNChanged,
    required this.size,
    required this.onSizeChanged,
    required this.aspectRatio,
    required this.onAspectRatioChanged,
    required this.useAspectRatio,
    required this.sizeOptions,
    required this.aspectOptions,
    required this.modelLabel,
    required this.enabled,
    required this.generating,
    required this.onGenerate,
    required this.onStop,
    this.quality = defaultImageQuality,
    this.onQualityChanged,
    this.supportsQuality = false,
    this.qualityOptions = imageQualityOptions,
    this.onPromptAssist,
    this.refBytes,
    this.onPickRef,
    this.onClearRef,
    this.onPickModel,
    this.modelPickerEnabled = true,
  });

  final String prompt;
  final ValueChanged<String> onPromptChanged;
  final int n;
  final ValueChanged<int> onNChanged;
  final String size;
  final ValueChanged<String> onSizeChanged;
  final String aspectRatio;
  final ValueChanged<String> onAspectRatioChanged;
  final bool useAspectRatio;
  final List<String> sizeOptions;
  final List<String> aspectOptions;
  final String modelLabel;
  final bool enabled;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onStop;
  final String quality;
  final ValueChanged<String>? onQualityChanged;
  final bool supportsQuality;
  final List<ImageQualityOption> qualityOptions;
  final VoidCallback? onPromptAssist;
  final Uint8List? refBytes;
  final VoidCallback? onPickRef;
  final VoidCallback? onClearRef;
  final VoidCallback? onPickModel;
  final bool modelPickerEnabled;

  @override
  State<ImageComposer> createState() => _ImageComposerState();
}

class _ImageComposerState extends State<ImageComposer> {
  late final TextEditingController _promptCtrl;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(text: widget.prompt);
  }

  @override
  void didUpdateWidget(covariant ImageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prompt != _promptCtrl.text &&
        widget.prompt != oldWidget.prompt) {
      _promptCtrl.text = widget.prompt;
      _promptCtrl.selection =
          TextSelection.collapsed(offset: _promptCtrl.text.length);
    }
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  bool get _canPickModel =>
      widget.modelPickerEnabled &&
      !widget.generating &&
      widget.onPickModel != null;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final hasRef = widget.refBytes != null && widget.refBytes!.isNotEmpty;
    final canPickModel = _canPickModel;

    return Card(
      margin: EdgeInsets.zero,
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '参数',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.modelLabel.isNotEmpty)
                  Flexible(
                    child: InkWell(
                      onTap: canPickModel ? widget.onPickModel : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          widget.modelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 11,
                            color: canPickModel
                                ? tokens.inkSecondary
                                : tokens.inkMuted,
                            fontFamily: tokens.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fieldLabel(tokens, '模型'),
                  const SizedBox(height: 6),
                  Material(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: canPickModel ? widget.onPickModel : null,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: tokens.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.modelLabel.isEmpty
                                    ? '未配置'
                                    : widget.modelLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: canPickModel
                                      ? tokens.ink
                                      : tokens.inkMuted,
                                  fontFamily: tokens.fontFamily,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: canPickModel
                                  ? tokens.inkSecondary
                                  : tokens.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: widget.useAspectRatio
                            ? _dropdown(
                                tokens: tokens,
                                label: '比例',
                                value: widget.aspectOptions
                                        .contains(widget.aspectRatio)
                                    ? widget.aspectRatio
                                    : widget.aspectOptions.first,
                                items: widget.aspectOptions,
                                enabled: !widget.generating,
                                onChanged: widget.onAspectRatioChanged,
                              )
                            : _dropdown(
                                tokens: tokens,
                                label: '尺寸',
                                value: widget.sizeOptions.contains(widget.size)
                                    ? widget.size
                                    : widget.sizeOptions.first,
                                items: widget.sizeOptions,
                                labelOf: (e) => e.replaceAll('x', '×'),
                                enabled: !widget.generating,
                                onChanged: widget.onSizeChanged,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dropdown<int>(
                          tokens: tokens,
                          label: '数量',
                          value: widget.n.clamp(1, 4),
                          items: const [1, 2, 3, 4],
                          labelOf: (e) => '$e',
                          enabled: !widget.generating,
                          onChanged: widget.onNChanged,
                        ),
                      ),
                    ],
                  ),
                  if (widget.supportsQuality) ...[
                    const SizedBox(height: 12),
                    _dropdown<String>(
                      tokens: tokens,
                      label: '质量',
                      value: widget.qualityOptions
                              .any((o) => o.value == widget.quality)
                          ? widget.quality
                          : defaultImageQuality,
                      items: [
                        for (final o in widget.qualityOptions) o.value,
                      ],
                      labelOf: (v) {
                        for (final o in widget.qualityOptions) {
                          if (o.value == v) return o.label;
                        }
                        return v;
                      },
                      enabled: !widget.generating,
                      onChanged: (v) => widget.onQualityChanged?.call(v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _fieldLabel(tokens, '提示词')),
                      TextButton(
                        onPressed: widget.generating
                            ? null
                            : widget.onPromptAssist,
                        child: const Text('辅助'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _promptCtrl,
                    onChanged:
                        widget.generating ? null : widget.onPromptChanged,
                    enabled: !widget.generating,
                    maxLines: 4,
                    minLines: 3,
                    decoration: InputDecoration(
                      hintText: '描述你想生成的画面…',
                      filled: true,
                      fillColor: tokens.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel(tokens, '参考图'),
                  const SizedBox(height: 6),
                  if (hasRef)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.memory(
                              widget.refBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: tokens.surface.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: '清除参考图',
                              icon: const Icon(Icons.close, size: 18),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                tapTargetSize: MaterialTapTargetSize.padded,
                              ),
                              onPressed: widget.generating
                                  ? null
                                  : widget.onClearRef,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    OutlinedButton.icon(
                      onPressed:
                          widget.generating ? null : widget.onPickRef,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('从相册选择参考图'),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SizedBox(
              height: 44,
              child: widget.generating
                  ? FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.danger,
                        foregroundColor: tokens.onPrimary,
                      ),
                      onPressed: widget.onStop,
                      child: const Text('停止生成'),
                    )
                  : FilledButton(
                      onPressed: widget.enabled ? widget.onGenerate : null,
                      child: Text(hasRef ? '图生图' : '生成'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(MaterialTokens tokens, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: tokens.inkSecondary,
        fontFamily: tokens.fontFamily,
      ),
    );
  }

  Widget _dropdown<T>({
    required MaterialTokens tokens,
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T> onChanged,
    String Function(T)? labelOf,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(tokens, label),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            filled: true,
            fillColor: tokens.surfaceMuted,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: [
                for (final e in items)
                  DropdownMenuItem(
                    value: e,
                    child: Text(labelOf?.call(e) ?? '$e'),
                  ),
              ],
              onChanged: enabled
                  ? (v) {
                      if (v != null) onChanged(v);
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
