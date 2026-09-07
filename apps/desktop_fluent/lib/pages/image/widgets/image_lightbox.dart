import 'dart:io';

import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// F-Lightbox：遮罩大图 + fade；Esc 关闭；多图左右键切换。
class ImageLightbox extends StatefulWidget {
  const ImageLightbox({
    super.key,
    required this.refs,
    required this.initialIndex,
    required this.bytesByIndex,
    required this.onClose,
    this.loadBytesFor,
    this.onSave,
  });

  final List<ImageRef> refs;
  final int initialIndex;
  final Map<int, Uint8List?> bytesByIndex;
  final VoidCallback onClose;
  final Future<Uint8List?> Function(ImageRef ref)? loadBytesFor;
  final Future<void> Function(ImageRef ref)? onSave;

  static Future<void> show(
    BuildContext context, {
    required ImageRef ref,
    required Future<Uint8List?> Function() loadBytes,
    Future<void> Function()? onSave,
    List<ImageRef>? refs,
    int initialIndex = 0,
    Future<Uint8List?> Function(ImageRef ref)? loadBytesFor,
    Future<void> Function(ImageRef ref)? onSaveRef,
  }) async {
    final list = (refs == null || refs.isEmpty) ? <ImageRef>[ref] : List<ImageRef>.from(refs);
    final start = initialIndex.clamp(0, list.length - 1);
    final loader = loadBytesFor;
    final bytesByIndex = <int, Uint8List?>{};
    if (loader != null) {
      bytesByIndex[start] = await loader(list[start]);
    } else {
      bytesByIndex[start] = await loadBytes();
    }
    if (!context.mounted) return;

    final saveFn = onSaveRef ??
        (onSave == null
            ? null
            : (ImageRef imageRef) async {
                if (imageRef.src == list[start].src) {
                  await onSave();
                }
              });

    final tokens = fluentTokensOf(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭预览',
      barrierColor: tokens.scrim,
      transitionDuration: FluentMotion.lightbox,
      pageBuilder: (ctx, animation, secondary) {
        return ImageLightbox(
          refs: list,
          initialIndex: start,
          bytesByIndex: bytesByIndex,
          loadBytesFor: loader,
          onClose: () => Navigator.of(ctx).pop(),
          onSave: saveFn,
        );
      },
      transitionBuilder: (ctx, animation, secondary, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: FluentMotion.standard,
          ),
          child: child,
        );
      },
    );
  }

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  late int _index;
  late final Map<int, Uint8List?> _bytes;
  late final FocusNode _focus;
  bool _loading = false;

  List<ImageRef> get _refs => widget.refs;
  bool get _multi => _refs.length > 1;
  ImageRef get _current => _refs[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.refs.length - 1);
    _bytes = Map<int, Uint8List?>.from(widget.bytesByIndex);
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ensureBytes(int index) async {
    if (_bytes.containsKey(index)) return;
    final loader = widget.loadBytesFor;
    setState(() => _loading = true);
    try {
      final ref = _refs[index];
      Uint8List? data;
      if (loader != null) {
        data = await loader(ref);
      } else if (ref.type == ImageRefType.file) {
        final file = File(ref.src);
        if (file.existsSync()) data = await file.readAsBytes();
      }
      if (mounted) {
        setState(() {
          _bytes[index] = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bytes[index] = null;
          _loading = false;
        });
      }
    }
  }

  void _go(int delta) {
    if (!_multi) return;
    final next = (_index + delta).clamp(0, _refs.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
    _ensureBytes(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final title = _multi ? '预览（${_index + 1}/${_refs.length}）' : '预览';
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        title: Row(
          children: [
            Expanded(child: Text(title)),
            if (_multi) ...[
              Tooltip(
                message: '上一张（←）',
                child: Semantics(
                  button: true,
                  label: '上一张',
                  child: IconButton(
                    icon: const Icon(FluentIcons.chevron_left),
                    onPressed: _index > 0 ? () => _go(-1) : null,
                  ),
                ),
              ),
              Tooltip(
                message: '下一张（→）',
                child: Semantics(
                  button: true,
                  label: '下一张',
                  child: IconButton(
                    icon: const Icon(FluentIcons.chevron_right),
                    onPressed:
                        _index < _refs.length - 1 ? () => _go(1) : null,
                  ),
                ),
              ),
            ],
            if (widget.onSave != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Button(
                  onPressed: () => widget.onSave!(_current),
                  child: const Text('另存为'),
                ),
              ),
            Tooltip(
              message: '关闭预览',
              child: Semantics(
                button: true,
                label: '关闭预览',
                excludeSemantics: true,
                child: IconButton(
                  icon: const Icon(FluentIcons.clear),
                  onPressed: widget.onClose,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 840,
          height: 560,
          child: Center(
            child: _loading && !_bytes.containsKey(_index)
                ? const ProgressRing()
                : _buildImage(_current, _bytes[_index]),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(ImageRef ref, Uint8List? bytes) {
    if (bytes != null && bytes.isNotEmpty) {
      return InteractiveViewer(
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    }
    if (ref.type == ImageRefType.file) {
      final file = File(ref.src);
      if (file.existsSync()) {
        return InteractiveViewer(
          child: Image.file(file, fit: BoxFit.contain),
        );
      }
    }
    if (ref.type == ImageRefType.url) {
      return InteractiveViewer(
        child: Image.network(ref.src, fit: BoxFit.contain),
      );
    }
    return const Text('无法显示图片');
  }
}
