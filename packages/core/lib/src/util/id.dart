import 'dart:math';

final _rand = Random.secure();

/// 生成本地实体 ID，如 `provider_a1b2c3d4`。
String createId(String prefix) {
  final suffix = List.generate(8, (_) => _rand.nextInt(16).toRadixString(16))
      .join();
  return '${prefix}_$suffix';
}
