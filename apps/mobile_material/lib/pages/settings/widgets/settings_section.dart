import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// A quiet surface for related settings, without a heavy floating-card effect.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.child,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Card(
      color: tokens.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: tokens.ink.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: tokens.border.withValues(alpha: 0.7)),
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

/// A small tonal marker makes groups scannable without adding extra headings.
class SettingsSectionHeading extends StatelessWidget {
  const SettingsSectionHeading({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = materialTokensOf(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: tokens.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: tokens.primaryPressed),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.ink,
              fontFamily: tokens.fontFamily,
            ),
          ),
        ),
      ],
    );
  }
}
