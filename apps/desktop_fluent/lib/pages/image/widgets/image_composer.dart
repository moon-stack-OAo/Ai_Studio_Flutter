import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../widgets/media_model_combo.dart';
import '../../../widgets/provider_models_cache.dart';

/// F-ImageParams + F-PromptBox + F-GenPrimary（右侧参数窗格，宽 300）。
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
    required this.providers,
    required this.modelsCache,
    required this.enabled,
    required this.generating,
    required this.onGenerate,
    required this.onStop,
    this.quality = defaultImageQuality,
    this.onQualityChanged,
    this.supportsQuality = false,
    this.qualityOptions = imageQualityOptions,
    this.onPromptAssist,
    this.referenceImage,
    this.loadReferenceBytes,
    this.onClearReference,
    this.onPickReference,
    this.onDropReference,
    this.onProviderSwitched,
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
  final ProviderRepository providers;
  final ProviderModelsCache modelsCache;
  final bool enabled;
  final bool generating;
  final VoidCallback onGenerate;
  final VoidCallback onStop;
  final String quality;
  final ValueChanged<String>? onQualityChanged;
  final bool supportsQuality;
  final List<ImageQualityOption> qualityOptions;
  final VoidCallback? onPromptAssist;
  final ImageRef? referenceImage;
  final Future<Uint8List?> Function(ImageRef ref)? loadReferenceBytes;
  final VoidCallback? onClearReference;
  final VoidCallback? onPickReference;
  final Future<void> Function(String path)? onDropReference;
  final VoidCallback? onProviderSwitched;

  @override
  State<ImageComposer> createState() => _ImageComposerState();
}

class _ImageComposerState extends State<ImageComposer> {
  late final TextEditingController _promptCtrl;

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

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(
              '参数',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              children: [
                _label(tokens, '模型'),
                const SizedBox(height: 6),
                MediaModelCombo(
                  providers: widget.providers,
                  modelsCache: widget.modelsCache,
                  kind: ModelKind.image,
                  currentModel: widget.modelLabel,
                  enabled: !widget.generating,
                  onProviderSwitched: widget.onProviderSwitched,
                ),
                const SizedBox(height: 12),
                _label(tokens, '数量'),
                const SizedBox(height: 6),
                _SegRow(
                  tokens: tokens,
                  children: [1, 2, 3, 4].map((v) {
                    return _SegItem(
                      label: '$v',
                      active: widget.n == v,
                      enabled: !widget.generating,
                      onTap: () => widget.onNChanged(v),
                      tokens: tokens,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                if (widget.useAspectRatio) ...[
                  _label(tokens, '比例'),
                  const SizedBox(height: 6),
                  _ChipWrap(
                    tokens: tokens,
                    options: widget.aspectOptions,
                    value: widget.aspectRatio,
                    enabled: !widget.generating,
                    onChanged: widget.onAspectRatioChanged,
                  ),
                ] else ...[
                  _label(tokens, '尺寸'),
                  const SizedBox(height: 6),
                  _ChipWrap(
                    tokens: tokens,
                    options: widget.sizeOptions,
                    value: widget.size,
                    enabled: !widget.generating,
                    labelOf: (e) => e.replaceAll('x', '×'),
                    onChanged: widget.onSizeChanged,
                  ),
                ],
                if (widget.supportsQuality) ...[
                  const SizedBox(height: 12),
                  _label(tokens, '质量'),
                  const SizedBox(height: 6),
                  _SegRow(
                    tokens: tokens,
                    children: widget.qualityOptions.map((opt) {
                      return _SegItem(
                        label: opt.label,
                        active: widget.quality == opt.value,
                        enabled: !widget.generating,
                        onTap: () => widget.onQualityChanged?.call(opt.value),
                        tokens: tokens,
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                _label(tokens, '提示词'),
                const SizedBox(height: 6),
                TextBox(
                  controller: _promptCtrl,
                  onChanged:
                      widget.generating ? null : widget.onPromptChanged,
                  maxLines: 6,
                  minLines: 4,
                  enabled: !widget.generating,
                  placeholder: '描述你想生成的画面…',
                  style: TextStyle(
                    fontFamily: tokens.fontFamily,
                    fontSize: 13,
                    height: 1.45,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 12),
                _label(tokens, '参考图'),
                const SizedBox(height: 6),
                _ReferenceBox(
                  tokens: tokens,
                  reference: widget.referenceImage,
                  loadBytes: widget.loadReferenceBytes,
                  onClear: widget.generating ? null : widget.onClearReference,
                  onPick: widget.generating ? null : widget.onPickReference,
                  onDrop: widget.generating ? null : widget.onDropReference,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 30,
                  child: Button(
                    onPressed: widget.generating ? null : widget.onPromptAssist,
                    child: Text(
                      '提示词辅助',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.generating
                            ? tokens.inkMuted
                            : tokens.inkSecondary,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: widget.generating
                      ? Button(
                          onPressed: widget.onStop,
                          style: ButtonStyle(
                            backgroundColor:
                                WidgetStatePropertyAll(tokens.danger),
                            foregroundColor:
                                const WidgetStatePropertyAll(Colors.white),
                          ),
                          child: const Text('停止生成'),
                        )
                      : FilledButton(
                          onPressed: widget.enabled ? widget.onGenerate : null,
                          child: const Text('生成'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(FluentTokens tokens, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: tokens.inkMuted,
        fontFamily: tokens.fontFamily,
      ),
    );
  }
}

class _SegRow extends StatelessWidget {
  const _SegRow({required this.tokens, required this.children});

  final FluentTokens tokens;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  const _SegItem({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
    required this.tokens,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  final FluentTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? tokens.primary.withValues(alpha: 0.20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: !enabled
                ? tokens.inkMuted
                : active
                    ? tokens.primaryPressed
                    : tokens.inkSecondary,
            fontFamily: tokens.fontFamily,
          ),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.tokens,
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.labelOf,
  });

  final FluentTokens tokens;
  final List<String> options;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((e) {
        final active = e == value;
        return GestureDetector(
          onTap: enabled ? () => onChanged(e) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? tokens.primary.withValues(alpha: 0.14)
                  : tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active
                    ? Color.lerp(tokens.primary, tokens.border, 0.5)!
                    : tokens.border,
              ),
            ),
            child: Text(
              labelOf?.call(e) ?? e,
              style: TextStyle(
                fontSize: 11,
                color: !enabled
                    ? tokens.inkMuted
                    : active
                        ? tokens.primaryPressed
                        : tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ReferenceBox extends StatefulWidget {
  const _ReferenceBox({
    required this.tokens,
    this.reference,
    this.loadBytes,
    this.onClear,
    this.onPick,
    this.onDrop,
  });

  final FluentTokens tokens;
  final ImageRef? reference;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;
  final VoidCallback? onClear;
  final VoidCallback? onPick;
  final Future<void> Function(String path)? onDrop;

  @override
  State<_ReferenceBox> createState() => _ReferenceBoxState();
}

class _ReferenceBoxState extends State<_ReferenceBox> {
  bool _dragging = false;

  Future<void> _handleDrop(DropDoneDetails detail) async {
    final onDrop = widget.onDrop;
    if (onDrop == null) return;
    if (detail.files.isEmpty) return;
    final path = detail.files.first.path.trim();
    if (path.isEmpty) return;
    await onDrop(path);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final hasRef = widget.reference != null;
    final canInteract = widget.onPick != null || widget.onDrop != null;
    final highlight = _dragging && widget.onDrop != null;
    return DropTarget(
      enable: widget.onDrop != null,
      onDragEntered: (_) {
        if (!_dragging) setState(() => _dragging = true);
      },
      onDragExited: (_) {
        if (_dragging) setState(() => _dragging = false);
      },
      onDragDone: (detail) async {
        if (_dragging) setState(() => _dragging = false);
        await _handleDrop(detail);
      },
      child: GestureDetector(
        onTap: hasRef || widget.onPick == null ? null : widget.onPick,
        child: MouseRegion(
          cursor: (!hasRef && canInteract)
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: highlight ? tokens.primary : tokens.border,
                style: BorderStyle.solid,
              ),
              color: highlight
                  ? tokens.primary.withValues(alpha: 0.08)
                  : tokens.canvas,
            ),
            child: hasRef
                ? Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: _RefThumb(
                            ref: widget.reference!,
                            loadBytes: widget.loadBytes,
                          ),
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
                              highlight ? '松开以替换参考图' : '图生图 · 可拖放替换',
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.inkMuted,
                                fontFamily: tokens.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.onClear != null)
                        HyperlinkButton(
                          onPressed: widget.onClear,
                          child: const Text('清除'),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      Text(
                        highlight ? '松开以设为参考' : '选择或拖放文件',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.inkSecondary,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '支持 PNG / JPEG / WebP',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
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

class _RefThumb extends StatefulWidget {
  const _RefThumb({required this.ref, this.loadBytes});

  final ImageRef ref;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytes;

  @override
  State<_RefThumb> createState() => _RefThumbState();
}

class _RefThumbState extends State<_RefThumb> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RefThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.src != widget.ref.src ||
        oldWidget.ref.type != widget.ref.type) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.ref.type == ImageRefType.url) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (widget.ref.type == ImageRefType.file) {
      final f = File(widget.ref.src);
      if (await f.exists()) {
        final b = await f.readAsBytes();
        if (mounted) {
          setState(() {
            _bytes = b;
            _loading = false;
          });
        }
        return;
      }
    }
    final loader = widget.loadBytes;
    if (loader != null) {
      final b = await loader(widget.ref);
      if (mounted) {
        setState(() {
          _bytes = b;
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: ProgressRing(strokeWidth: 2));
    }
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: BoxFit.cover);
    }
    if (widget.ref.type == ImageRefType.url) {
      return Image.network(widget.ref.src, fit: BoxFit.cover);
    }
    return const Center(child: Icon(FluentIcons.photo, size: 18));
  }
}
