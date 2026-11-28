import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 桌面端全页空态（未配置提供商等）：短文案 + 主按钮。
class FluentFeatureEmpty extends StatelessWidget {
  const FluentFeatureEmpty({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.onAction,
    this.illustration,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ColoredBox(
      color: tokens.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _FluentEmptyAppear(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (illustration != null) ...[
                    illustration!,
                    const SizedBox(height: 16),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
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
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    button: true,
                    label: actionLabel,
                    excludeSemantics: true,
                    child: FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左窗格会话列表空态：与真实行同高的一行（状态点 + 文字 + 文字按钮）。
class FluentSessionListEmpty extends StatelessWidget {
  const FluentSessionListEmpty({
    super.key,
    required this.onCreate,
    this.title = '暂无会话',
    this.actionLabel = '新建会话',
    this.verticalPadding = 8,
  });

  final VoidCallback onCreate;
  final String title;
  final String actionLabel;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: _FluentListEmptyRow(
        label: title,
        actionLabel: actionLabel,
        onAction: onCreate,
        verticalPadding: verticalPadding,
      ),
    );
  }
}

/// 未配置提供商的整屏空态：左对齐，标题 + 一句说明 + 一枚状态点熄灭的
/// 配置卡片。三处入口（对话 / 生图 / 生视频）只换文案。
class FluentUnconfiguredEmpty extends StatelessWidget {
  const FluentUnconfiguredEmpty({
    super.key,
    required this.kind,
    this.onAction,
  });

  final ModelKind kind;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final (title, message, cardTitle, cardHint) = switch (kind) {
      ModelKind.image => (
        '还没有可用的生图模型',
        '添加一个提供商，填上 Key 并选择生图模型。',
        '生图',
        '未选择模型',
      ),
      ModelKind.video => (
        '还没有可用的视频模型',
        '添加一个提供商，填上 Key 并选择视频模型。',
        '生视频',
        '未选择模型',
      ),
      _ => (
        '还没有可用的模型',
        '添加一个提供商，填上 Key 并选择对话模型。',
        '对话',
        '未选择模型',
      ),
    };
    return ColoredBox(
      color: tokens.canvas,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 56, 40, 32),
            child: _FluentEmptyAppear(
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
                      fontSize: 13,
                      height: 1.5,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: tokens.inkMuted,
                                width: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cardTitle,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.ink,
                                    fontFamily: tokens.fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  cardHint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.inkMuted,
                                    fontFamily: tokens.monoFontFamily,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '添加提供商',
                            excludeSemantics: true,
                            child: Button(
                              onPressed: onAction,
                              child: const Text('添加提供商'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 内容区简洁空提示（消息 / 时间线 / 队列）。
class FluentContentEmpty extends StatelessWidget {
  const FluentContentEmpty({
    super.key,
    required this.hint,
    this.subtitle,
    this.illustration,
    this.actionLabel,
    this.onAction,
    this.hintStyle,
    this.subtitleStyle,
  });

  final String hint;
  final String? subtitle;
  final Widget? illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final TextStyle? hintStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final showAction =
        actionLabel != null && actionLabel!.isNotEmpty && onAction != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: _FluentEmptyAppear(
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
                style:
                    hintStyle ??
                    TextStyle(
                      fontSize: 13,
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
                  style:
                      subtitleStyle ??
                      TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                ),
              ],
              if (showAction) ...[
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  label: actionLabel,
                  excludeSemantics: true,
                  child: FilledButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
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

/// 设置 · 提供商列表空态：与列表行对齐的一行（状态点 + 文字 + 文字按钮）。
class FluentProvidersListEmpty extends StatelessWidget {
  const FluentProvidersListEmpty({super.key, this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
      child: _FluentListEmptyRow(
        label: '暂无提供商',
        actionLabel: onAdd == null ? null : '添加提供商',
        onAction: onAdd,
        verticalPadding: 12,
        horizontalPadding: 12,
        radius: 10,
      ),
    );
  }
}

/// 列表窗格里的空态行：左侧一枚熄灭的状态点，中间文字，右侧文字按钮。
/// 高度跟调用方传入的内边距走，与对应列表的真实行对齐。
class _FluentListEmptyRow extends StatelessWidget {
  const _FluentListEmptyRow({
    required this.label,
    required this.verticalPadding,
    this.actionLabel,
    this.onAction,
    this.horizontalPadding = 10,
    this.radius = 8,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double verticalPadding;
  final double horizontalPadding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    final showAction =
        actionLabel != null && actionLabel!.isNotEmpty && onAction != null;
    return _FluentEmptyAppear(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          verticalPadding,
          showAction ? 4 : horizontalPadding,
          verticalPadding,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: tokens.inkMuted, width: 1.4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tokens.inkSecondary,
                  fontFamily: tokens.fontFamily,
                ),
              ),
            ),
            if (showAction)
              Semantics(
                button: true,
                label: actionLabel,
                excludeSemantics: true,
                child: HyperlinkButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 生图 / 生视频结果区空态：一帧发丝线画框，表示结果将出现在这里。
/// 画幅由调用方按页面默认比例给出，下方一行等宽小字写真实默认参数。
class FluentResultFrameEmpty extends StatelessWidget {
  const FluentResultFrameEmpty({
    super.key,
    required this.aspectRatio,
    required this.caption,
  });

  final double aspectRatio;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: _FluentEmptyAppear(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: CustomPaint(
                    painter: _FluentHairlineGridPainter(color: tokens.border),
                  ),
                ),
                const SizedBox(height: 8),
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

/// 1px 发丝线外框 + 三分网格，颜色取自 token。
class _FluentHairlineGridPainter extends CustomPainter {
  const _FluentHairlineGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
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
  bool shouldRepaint(covariant _FluentHairlineGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _FluentEmptyAppear extends StatefulWidget {
  const _FluentEmptyAppear({required this.child});

  final Widget child;

  @override
  State<_FluentEmptyAppear> createState() => _FluentEmptyAppearState();
}

class _FluentEmptyAppearState extends State<_FluentEmptyAppear> {
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
      duration: FluentMotion.listAppear,
      curve: FluentMotion.standard,
      child: widget.child,
    );
  }
}
