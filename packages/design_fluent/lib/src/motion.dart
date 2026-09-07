import 'package:flutter/animation.dart';

/// Fluent 短动效时长（可打断、不挡操作）。
abstract final class FluentMotion {
  static const Duration sectionSwitch = Duration(milliseconds: 140);
  static const Duration listAppear = Duration(milliseconds: 160);
  static const Duration lightbox = Duration(milliseconds: 180);
  static const Duration micro = Duration(milliseconds: 120);

  static const Curve standard = Curves.easeOut;
}
