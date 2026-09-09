/// 更新说明展示前准备：去掉损坏文本、过长截断；**保留 Markdown** 供 UI 渲染。
String prepareUpdateNotes(String raw, {int maxChars = 2000}) {
  var text = raw.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) return '';

  // UTF-8 解码失败常见替换符；大量 � 说明清单编码坏了。
  final replacementCount = RegExp(r'\uFFFD').allMatches(text).length;
  if (replacementCount >= 3) return '';

  // 收敛多余空行，避免弹窗过高。
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}\n\n…';
}

/// @Deprecated 使用 [prepareUpdateNotes]；旧名保留以免外部调用断裂。
String sanitizeUpdateNotes(String raw, {int maxChars = 2000}) =>
    prepareUpdateNotes(raw, maxChars: maxChars);
