// 助手消息元信息展示（CHAT-MSG-META）：`模型 · 耗时`。

/// 将毫秒耗时格式化为自适应中文文案。
///
/// - `<1秒` → `N毫秒`（如 `850毫秒`）
/// - `<60秒` → `N秒`（整秒，如 `52秒`）
/// - `≥60秒` → `x分x秒`；秒为 0 时写 `x分`（如 `1分`、`1分23秒`）
String formatChatLatency(int latencyMs) {
  if (latencyMs < 0) latencyMs = 0;
  if (latencyMs < 1000) {
    return '$latencyMs毫秒';
  }
  final totalSeconds = latencyMs ~/ 1000;
  if (totalSeconds < 60) {
    return '$totalSeconds秒';
  }
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  if (seconds == 0) {
    return '$minutes分';
  }
  return '$minutes分$seconds秒';
}

/// 组装角色旁展示文案；流式中可仅显模型（不传 [latencyMs]）。
///
/// 返回 `null` 表示无可展示内容。
String? formatChatMessageMeta({
  String? model,
  int? latencyMs,
  bool streaming = false,
}) {
  final name = model?.trim() ?? '';
  if (name.isEmpty) {
    if (streaming || latencyMs == null) return null;
    return formatChatLatency(latencyMs);
  }
  if (streaming || latencyMs == null) {
    return name;
  }
  return '$name · ${formatChatLatency(latencyMs)}';
}
