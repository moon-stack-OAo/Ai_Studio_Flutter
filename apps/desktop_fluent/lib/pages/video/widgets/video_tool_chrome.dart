import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 对齐 OD `.tool` / transport 控件的桌面播放器按钮 chrome。
ButtonStyle videoToolButtonStyle(
  FluentTokens tokens, {
  required double height,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 10),
}) {
  return ButtonStyle(
    padding: WidgetStatePropertyAll(padding),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.isDisabled) {
        return tokens.surfaceMuted;
      }
      return tokens.surface;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.isDisabled) return tokens.inkMuted;
      if (states.isHovered || states.isPressed) return tokens.primary;
      return tokens.ink;
    }),
    shape: WidgetStateProperty.resolveWith((states) {
      final borderColor = states.isDisabled
          ? tokens.border
          : (states.isHovered || states.isPressed || states.isFocused)
              ? tokens.primary
              : tokens.border;
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: borderColor),
      );
    }),
    textStyle: WidgetStatePropertyAll(
      TextStyle(
        fontSize: 11,
        fontFamily: tokens.fontFamily,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// 动作区次要按钮（OD `.player-wrap > .job-actions .tool`：高 30）。
class VideoToolButton extends StatelessWidget {
  const VideoToolButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.filled = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    if (filled) {
      return SizedBox(
        height: 30,
        child: FilledButton(
          onPressed: onPressed,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(
                fontSize: 11,
                fontFamily: tokens.fontFamily,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      height: 30,
      child: Button(
        onPressed: onPressed,
        style: videoToolButtonStyle(tokens, height: 30),
        child: child,
      ),
    );
  }
}

/// transport 图标钮（OD `.transport > .tool`：32×32）。
class VideoTransportIconButton extends StatelessWidget {
  const VideoTransportIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel ?? tooltip,
        excludeSemantics: true,
        child: HoverButton(
          onPressed: onPressed,
          builder: (context, states) {
            final hovered = states.isHovered || states.isPressed;
            final focused = states.isFocused;
            final borderColor = !enabled
                ? tokens.border
                : (hovered || focused)
                    ? tokens.primary
                    : tokens.border;
            final fg = !enabled
                ? tokens.inkMuted
                : hovered
                    ? tokens.primary
                    : tokens.ink;
            return Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: Icon(icon, size: 14, color: fg),
            );
          },
        ),
      ),
    );
  }
}
