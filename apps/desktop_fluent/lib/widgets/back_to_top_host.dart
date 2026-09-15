import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 设置等可滚动页的「回到顶部」浮层：滚过阈值后右下角圆形上箭头，Tooltip 文案。
class BackToTopHost extends StatefulWidget {
  const BackToTopHost({
    super.key,
    required this.builder,
    this.threshold = 80,
    this.right = 28,
    this.bottom = 28,
  });

  /// 须把 [ScrollController] 交给可滚动子树（如 ListView.controller）。
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  final double threshold;
  final double right;
  final double bottom;

  @override
  State<BackToTopHost> createState() => _BackToTopHostState();
}

class _BackToTopHostState extends State<BackToTopHost> {
  late final ScrollController _scroll = ScrollController();
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final show = _scroll.hasClients && _scroll.offset > widget.threshold;
    if (show != _show) setState(() => _show = show);
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.builder(context, _scroll)),
        Positioned(
          right: widget.right,
          bottom: widget.bottom,
          child: IgnorePointer(
            ignoring: !_show,
            child: AnimatedOpacity(
              opacity: _show ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: BackToTopButton(onPressed: _scrollToTop),
            ),
          ),
        ),
      ],
    );
  }
}

class BackToTopButton extends StatelessWidget {
  const BackToTopButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Tooltip(
      message: '回到顶部',
      child: HoverButton(
        onPressed: onPressed,
        builder: (ctx, states) {
          final hovered = states.isHovered || states.isPressed;
          return Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hovered
                  ? Color.lerp(tokens.primary, tokens.surface, 0.12)
                  : tokens.surface,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.border),
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, hovered ? 0.18 : 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              FluentIcons.up,
              size: 14,
              color: tokens.inkSecondary,
            ),
          );
        },
      ),
    );
  }
}
