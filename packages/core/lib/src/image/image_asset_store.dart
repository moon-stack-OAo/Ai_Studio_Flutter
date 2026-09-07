import 'dart:convert';
import 'dart:typed_data';

/// 生图二进制落盘抽象（桌面用 path_provider 文件实现；测试用内存）。
abstract class ImageAssetStore {
  /// 保存 PNG 字节，返回可供 [ImageRef] 使用的本地路径或稳定 id。
  Future<String> savePng(Uint8List bytes, String id);

  /// 按路径/id 读取字节；不存在返回 null。
  Future<Uint8List?> read(String pathOrId);

  /// 删除缓存；忽略不存在。
  Future<void> delete(String pathOrId);

  /// 清空全部媒体缓存（幂等）。
  Future<void> clearAll();

  /// 估算缓存占用字节。
  Future<int> estimateBytes();
}

/// 内存实现：路径形如 `memory://{id}`。
class MemoryImageAssetStore implements ImageAssetStore {
  final Map<String, Uint8List> _map = {};

  Map<String, Uint8List> get entries => Map.unmodifiable(_map);

  @override
  Future<String> savePng(Uint8List bytes, String id) async {
    final key = 'memory://$id';
    _map[key] = Uint8List.fromList(bytes);
    return key;
  }

  @override
  Future<Uint8List?> read(String pathOrId) async => _map[pathOrId];

  @override
  Future<void> delete(String pathOrId) async {
    _map.remove(pathOrId);
  }

  @override
  Future<void> clearAll() async {
    _map.clear();
  }

  @override
  Future<int> estimateBytes() async {
    var total = 0;
    for (final bytes in _map.values) {
      total += bytes.length;
    }
    return total;
  }
}

/// 从 b64 / data URL 解码 PNG 字节。
Uint8List? decodeImageB64(String src) {
  var s = src.trim();
  if (s.isEmpty) return null;
  final comma = s.indexOf(',');
  if (s.startsWith('data:') && comma >= 0) {
    s = s.substring(comma + 1);
  }
  try {
    return base64Decode(s);
  } catch (_) {
    return null;
  }
}

/// 将纯 base64 规范为 data URL。
String toDataUrlPng(String b64OrDataUrl) {
  final s = b64OrDataUrl.trim();
  if (s.startsWith('data:')) return s;
  return 'data:image/png;base64,$s';
}
