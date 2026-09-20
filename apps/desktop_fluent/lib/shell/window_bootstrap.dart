import 'dart:io' show Platform;

import 'package:design_fluent/design_fluent.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// 是否为可自定义标题栏的桌面端（排除测试/非桌面）。
bool get supportsCustomTitleBar {
  if (kIsWeb) return false;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  try {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  } catch (_) {
    return false;
  }
}

/// 原生窗底色：须不透明。透明底在最大化拉大时会先露出桌面，整窗闪一下。
Color desktopWindowBackgroundFor(Brightness brightness) =>
    FluentTokens.ofBrightness(brightness).canvas;

/// 无边框自定义标题栏初始化（方案 B）。
Future<void> bootstrapDesktopWindow({
  Brightness brightness = Brightness.light,
}) async {
  if (!supportsCustomTitleBar) return;

  await windowManager.ensureInitialized();

  final background = desktopWindowBackgroundFor(brightness);
  final options = WindowOptions(
    size: const Size(1280, 820),
    minimumSize: const Size(960, 640),
    center: true,
    backgroundColor: background,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    title: 'AI Studio',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setBackgroundColor(background);
    if (Platform.isWindows) {
      await windowManager.setBrightness(brightness);
    }
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 主题切换后同步原生窗底，避免暗色 UI 下仍闪浅色底（或反之）。
Future<void> syncDesktopWindowBackground(Brightness brightness) async {
  if (!supportsCustomTitleBar) return;
  await windowManager.setBackgroundColor(
    desktopWindowBackgroundFor(brightness),
  );
  if (Platform.isWindows) {
    await windowManager.setBrightness(brightness);
  }
}
