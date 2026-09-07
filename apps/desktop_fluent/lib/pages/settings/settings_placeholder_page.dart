import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

class SettingsPlaceholderPage extends StatelessWidget {
  const SettingsPlaceholderPage({
    super.key,
    required this.title,
    required this.lead,
    this.badge,
  });

  final String title;
  final String lead;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final tokens = fluentTokensOf(context);
    return ColoredBox(
      color: tokens.canvas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
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
          const SizedBox(height: 6),
          Text(
            lead,
            style: TextStyle(
              fontSize: 13,
              color: tokens.inkMuted,
              fontFamily: tokens.fontFamily,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
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
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Text(
              '占位内容 · 业务表单下一轮接入',
              style: TextStyle(
                fontSize: 13,
                color: tokens.inkSecondary,
                fontFamily: tokens.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
