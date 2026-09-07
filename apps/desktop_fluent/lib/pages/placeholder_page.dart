import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.subtitle,
    this.badge,
    this.child,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: ColoredBox(
        color: tokens.canvas,
        child: child ??
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: tokens.inkMuted,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: tokens.border,
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              color: tokens.inkMuted,
                            ).withMonoFont(tokens),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
