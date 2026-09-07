import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// 当前运行时对应的桌面更新清单平台键候选（按优先级）。
///
/// 约定键：`windows-x86_64`、`windows-x86_64-nsis`、`windows-x86_64-msi` 等。
List<String> desktopUpdatePlatformCandidates({
  bool? isWindows,
  bool? isMacOS,
  bool? isLinux,
  String? macArch,
}) {
  if (kIsWeb) return const [];

  final win = isWindows ?? Platform.isWindows;
  final mac = isMacOS ?? Platform.isMacOS;
  final linux = isLinux ?? Platform.isLinux;

  if (win) {
    return const [
      'windows-x86_64',
      'windows-x86_64-nsis',
      'x86_64-pc-windows-msvc',
      'windows-x86_64-msi',
    ];
  }
  if (mac) {
    final arch = (macArch ?? Platform.version).toLowerCase();
    // Platform.version 含 arch 信息有限；优先按宿主进程位数启发式。
    final preferArm = arch.contains('arm') ||
        arch.contains('aarch64') ||
        _hostLooksArm();
    if (preferArm) {
      return const [
        'darwin-aarch64',
        'aarch64-apple-darwin',
        'darwin-x86_64',
        'x86_64-apple-darwin',
      ];
    }
    return const [
      'darwin-x86_64',
      'x86_64-apple-darwin',
      'darwin-aarch64',
      'aarch64-apple-darwin',
    ];
  }
  if (linux) {
    return const [
      'linux-x86_64',
      'x86_64-unknown-linux-gnu',
    ];
  }
  return const [];
}

/// Android 侧载清单平台键候选（按优先级）。
///
/// 默认：`aarch64-linux-android` → `arm64-v8a` → …
List<String> androidUpdatePlatformCandidates({
  String? abiHint,
}) {
  final hint = (abiHint ?? '').trim().toLowerCase();
  if (hint.contains('armeabi') || hint.contains('armv7') || hint == 'armeabi-v7a') {
    return const [
      'armeabi-v7a',
      'armv7-linux-androideabi',
      'aarch64-linux-android',
      'arm64-v8a',
      'x86_64',
      'x86_64-linux-android',
    ];
  }
  if (hint.contains('x86_64') || hint.contains('x86-64')) {
    return const [
      'x86_64',
      'x86_64-linux-android',
      'aarch64-linux-android',
      'arm64-v8a',
    ];
  }
  // 默认优先 64-bit ARM（主流真机）。
  return const [
    'aarch64-linux-android',
    'arm64-v8a',
    'armeabi-v7a',
    'armv7-linux-androideabi',
    'x86_64',
    'x86_64-linux-android',
  ];
}

bool _hostLooksArm() {
  try {
    // Dart VM 在 Apple Silicon 上通常为 arm64。
    return Platform.localHostname.isNotEmpty &&
        Platform.operatingSystemVersion.toLowerCase().contains('arm');
  } catch (_) {
    return false;
  }
}
