import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'window_bootstrap.dart';

/// Fluent 自定义标题栏（F-TitleBar / NAV-TITLE）。
///
/// 桌面：隐藏系统栏 + 拖拽区 + 自绘 min/max/close。
/// 非桌面 / 测试：同视觉条，无窗口控点。
class FluentAppTitleBar extends StatefulWidget {
  const FluentAppTitleBar({
    super.key,
    required this.title,
    this.endActions,
    this.height = 36,
    this.onClose,
  });

  final String title;
  final List<Widget>? endActions;
  final double height;

  /// 关闭请求；未提供时走 `windowManager.close()`（仍受 setPreventClose 拦截）。
  final Future<void> Function()? onClose;

  @override
  State<FluentAppTitleBar> createState() => _FluentAppTitleBarState();
}

class _FluentAppTitleBarState extends State<FluentAppTitleBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (supportsCustomTitleBar) {
      windowManager.addListener(this);
      _refreshMaximized();
    }
  }

  @override
  void dispose() {
    if (supportsCustomTitleBar) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    if (!supportsCustomTitleBar) return;
    final value = await windowManager.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = value);
  }

  @override
  void onWindowMaximize() => _refreshMaximized();

  @override
  void onWindowUnmaximize() => _refreshMaximized();

  @override
  void onWindowRestore() => _refreshMaximized();

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final brightness = tokens.brightness;
    final bar = SizedBox(
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(tokens.surface, tokens.surfaceMuted, 0.35),
          border: Border(
            bottom: BorderSide(color: tokens.border),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: _buildDragTitle(tokens)),
            if (widget.endActions != null) ...[
              ...widget.endActions!,
              const SizedBox(width: 4),
            ],
            if (supportsCustomTitleBar) _buildWindowControls(brightness),
          ],
        ),
      ),
    );

    if (!supportsCustomTitleBar) return bar;
    return bar;
  }

  Widget _buildDragTitle(FluentTokens tokens) {
    final content = Padding(
      padding: const EdgeInsetsDirectional.only(start: 14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'assets/logo.png',
              width: 16,
              height: 16,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: tokens.primary,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );

    if (!supportsCustomTitleBar) {
      return Align(alignment: Alignment.centerLeft, child: content);
    }

    return DragToMoveArea(
      child: SizedBox(
        height: double.infinity,
        child: Align(alignment: Alignment.centerLeft, child: content),
      ),
    );
  }

  Widget _buildWindowControls(Brightness brightness) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: brightness,
          onPressed: () async {
            final minimized = await windowManager.isMinimized();
            if (minimized) {
              await windowManager.restore();
            } else {
              await windowManager.minimize();
            }
          },
        ),
        if (_maximized)
          WindowCaptionButton.unmaximize(
            brightness: brightness,
            onPressed: () => windowManager.unmaximize(),
          )
        else
          WindowCaptionButton.maximize(
            brightness: brightness,
            onPressed: () => windowManager.maximize(),
          ),
        WindowCaptionButton.close(
          brightness: brightness,
          onPressed: () {
            final close = widget.onClose;
            if (close != null) {
              close();
            } else {
              windowManager.close();
            }
          },
        ),
      ],
    );
  }
}
