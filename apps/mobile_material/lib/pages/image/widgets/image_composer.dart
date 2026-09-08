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
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: canPickModel ? widget.onPickModel : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.modelLabel.isEmpty
                                    ? '未配置模型'
                                    : widget.modelLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: canPickModel
                                      ? tokens.inkSecondary
                                      : tokens.inkMuted,
                                  fontFamily: tokens.fontFamily,
                                ),
                              ),
                            ),
                            if (canPickModel) ...[
                              const SizedBox(width: 2),
                              Icon(
                                Icons.expand_more,
                                size: 16,
                                color: tokens.inkMuted,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? '收起参数' : '展开参数',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: tokens.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      const SizedBox(width: 8),
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
                      if (widget.supportsQuality) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _dropdown<String>(
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
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _fieldLabel(tokens, '提示词')),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: widget.generating
                            ? null
                            : widget.onPromptAssist,
                        child: const Text('辅助'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    textField: true,
                    label: '提示词',
                    child: TextField(
                      controller: _promptCtrl,
                      onChanged:
                          widget.generating ? null : widget.onPromptChanged,
                      enabled: !widget.generating,
                      maxLines: 3,
                      minLines: 2,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: tokens.fontFamily,
                      ),
                      decoration: InputDecoration(
                        hintText: '描述你想生成的画面…',
                        isDense: true,
                        filled: true,
                        fillColor: tokens.surfaceMuted,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _fieldLabel(tokens, '参考图'),
                  const SizedBox(height: 4),
                  if (hasRef)
                    _RefThumbRow(
                      tokens: tokens,
                      bytes: widget.refBytes!,
                      enabled: !widget.generating,
                      onClear: widget.onClearRef,
                      onReplace: widget.onPickRef,
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size.fromHeight(40),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed:
                          widget.generating ? null : widget.onPickRef,
                      icon: const Icon(Icons.add_photo_alternate_outlined,
                          size: 18),
                      label: const Text('从相册选择参考图'),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              height: 44,
              child: widget.generating
                  ? Semantics(
                      button: true,
                      label: '停止生成',
                      excludeSemantics: true,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.danger,
                          foregroundColor: tokens.onPrimary,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: widget.onStop,
                        child: const Text('停止生成'),
                      ),
                    )
                  : Semantics(
                      button: true,
                      label: hasRef ? '图生图' : '生成图片',
                      excludeSemantics: true,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: widget.enabled ? widget.onGenerate : null,
                        child: Text(hasRef ? '图生图' : '生成'),
                      ),
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
        fontSize: 11,
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
        const SizedBox(height: 4),
        InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: tokens.surfaceMuted,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                fontSize: 13,
                color: tokens.ink,
                fontFamily: tokens.fontFamily,
              ),
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

class _RefThumbRow extends StatelessWidget {
  const _RefThumbRow({
    required this.tokens,
    required this.bytes,
    required this.enabled,
    this.onClear,
    this.onReplace,
  });

  final MaterialTokens tokens;
  final Uint8List bytes;
  final bool enabled;
  final VoidCallback? onClear;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onReplace : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已设为参考',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled ? '点击可更换' : '生成中',
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '清除参考图',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(40, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.close, size: 18, color: tokens.inkMuted),
                onPressed: enabled ? onClear : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
