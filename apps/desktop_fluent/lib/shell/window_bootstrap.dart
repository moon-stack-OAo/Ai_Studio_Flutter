import 'dart:io' show Platform;

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

/// 无边框自定义标题栏初始化（方案 B）。
Future<void> bootstrapDesktopWindow() async {
  if (!supportsCustomTitleBar) return;

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(960, 640),
    center: true,
    backgroundColor: Color(0x00000000),
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
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
}
