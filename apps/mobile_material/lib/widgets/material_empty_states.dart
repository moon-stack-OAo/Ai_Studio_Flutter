import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// 未配置模型的整屏空态：左对齐标题与说明，下面一枚熄灭的模型卡片。
///
/// 卡片右侧按钮只在调用方已有「打开提供商」回调时出现，不另造入口。
class MaterialFeatureEmpty extends StatelessWidget {
  const MaterialFeatureEmpty({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.onOpenProviders,
    this.appBarTitle,
  });

  final ModelKind kind;
  final String title;
  final String message;
  final VoidCallback? onOpenProviders;
  final String? appBarTitle;

  String get _cardTitle => switch (kind) {
    ModelKind.image => '生图',
    ModelKind.video => '生视频',
    _ => '对话',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final body = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          child: _MaterialEmptyAppear(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: tokens.ink,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
                const SizedBox(height: 20),
                _UnconfiguredModelCard(
                  title: _cardTitle,
                  onOpenProviders: onOpenProviders,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (appBarTitle == null) {
      return ColoredBox(color: tokens.canvas, child: body);
    }

    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(title: Text(appBarTitle!)),
      body: body,
    );
  }
}

/// 熄灭的模型选择卡片：7px 空心状态点 + 场景名 + 等宽「未选择模型」。
class _UnconfiguredModelCard extends StatelessWidget {
  const _UnconfiguredModelCard({required this.title, this.onOpenProviders});

  final String title;
  final VoidCallback? onOpenProviders;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const _StatusDot(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '未选择模型',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkMuted,
                      fontFamily: tokens.monoFontFamily,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (onOpenProviders != null)
              TextButton(
                onPressed: onOpenProviders,
                child: const Text('添加提供商'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 7px 空心状态点，表示当前没有可用模型。
class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.inkMuted, width: 1.4),
      ),
    );
  }
}

/// 会话列表空态：与真实行同高的一行，左侧状态点 + 文字 + 文字按钮。
class MaterialSessionListEmpty extends StatelessWidget {
  const MaterialSessionListEmpty({
    super.key,
    required this.onCreate,
    this.title = '暂无会话',
    this.actionLabel = '新建会话',
    this.dense = false,
    this.verticalPadding = 10,
  });

  final VoidCallback onCreate;
  final String title;
  final String actionLabel;

  /// 生图 / 生视频会话行是双行 ListTile，用更高的内边距对齐。
  final bool dense;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return _MaterialEmptyAppear(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 48 : 72),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              const _StatusDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
              TextButton(onPressed: onCreate, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行文字空提示。消息列表只留这一行，不再带插画、标题或按钮。
class MaterialContentEmpty extends StatelessWidget {
  const MaterialContentEmpty({
    super.key,
    required this.hint,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    this.illustration,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String hint;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    final showAction =
        actionLabel != null && actionLabel!.isNotEmpty && onAction != null;
    final showSecondary =
        secondaryActionLabel != null &&
        secondaryActionLabel!.isNotEmpty &&
        onSecondaryAction != null;
    return Padding(
      padding: padding,
      child: Center(
        child: _MaterialEmptyAppear(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustration != null) ...[
                illustration!,
                const SizedBox(height: 10),
              ],
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tokens.inkSecondary,
                  fontFamily: tokens.fontFamily,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: tokens.inkMuted,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ],
              if (showAction || showSecondary) ...[
                const SizedBox(height: 16),
                if (showAction)
                  Semantics(
                    button: true,
                    label: actionLabel,
                    excludeSemantics: true,
                    child: FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(160, 44),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
                if (showAction && showSecondary) const SizedBox(height: 10),
                if (showSecondary)
                  Semantics(
                    button: true,
                    label: secondaryActionLabel,
                    excludeSemantics: true,
                    child: OutlinedButton(
                      onPressed: onSecondaryAction,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(160, 44),
                      ),
                      child: Text(secondaryActionLabel!),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 生图 / 生视频空结果：发丝线空网格，下方一行等宽小字写真实默认参数。
///
/// 无标题、无按钮——生成入口在页面自己的表单里。
class MaterialResultFrameEmpty extends StatelessWidget {
  const MaterialResultFrameEmpty({
    super.key,
    required this.aspectRatio,
    required this.caption,
  });

  final double aspectRatio;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: _MaterialEmptyAppear(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: CustomPaint(
                    painter: _HairlineGridPainter(color: tokens.border),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.inkMuted,
                    fontFamily: tokens.monoFontFamily,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// 1px 外框加三分网格，颜色取自 token 的发丝线。
class _HairlineGridPainter extends CustomPainter {
  const _HairlineGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, paint);
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HairlineGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 设置 · 提供商列表空态：与列表行同高的一行。
class MaterialProvidersListEmpty extends StatelessWidget {
  const MaterialProvidersListEmpty({super.key, this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return _MaterialEmptyAppear(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const _StatusDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '暂无提供商',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: tokens.inkSecondary,
                    fontFamily: tokens.fontFamily,
                  ),
                ),
              ),
              if (onAdd != null)
                TextButton(onPressed: onAdd, child: const Text('添加提供商')),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialEmptyAppear extends StatefulWidget {
  const _MaterialEmptyAppear({required this.child});

  final Widget child;

  @override
  State<_MaterialEmptyAppear> createState() => _MaterialEmptyAppearState();
}

class _MaterialEmptyAppearState extends State<_MaterialEmptyAppear> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: MaterialMotion.listAppear,
      curve: MaterialMotion.standard,
      child: widget.child,
    );
  }
}
