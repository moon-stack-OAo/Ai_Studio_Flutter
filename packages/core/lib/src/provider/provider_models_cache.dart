import 'dart:async';

import 'package:flutter/foundation.dart';

import 'provider_config.dart';
import 'provider_connection.dart';
import 'provider_repository.dart';

/// 提供商模型列表 TTL 缓存（对话 / 生图 / 生视频共用）。
///
/// 自身为 [ChangeNotifier]；可选再回调宿主 [onChanged]（供页面 Listenable 合并）。
class ProviderModelsCache extends ChangeNotifier {
  ProviderModelsCache({
    required this.providers,
    this.onChanged,
  });

  static const Duration ttl = Duration(minutes: 5);

  final ProviderRepository providers;
  final VoidCallback? onChanged;

  final Map<String, List<ProviderModelInfo>> _cache = {};
  final Map<String, DateTime> _cacheAt = {};
  bool _loading = false;
  String? _error;

  bool get loading => _loading;

  String? get error => _error;

  List<ProviderModelInfo> get cachedForActive {
    final id = providers.activeProvider?.id;
    if (id == null) return const [];
    return List.unmodifiable(_cache[id] ?? const []);
  }

  bool get hasCached => cachedForActive.isNotEmpty;

  bool get isFresh {
    final id = providers.activeProvider?.id;
    if (id == null) return false;
    return _cacheFresh(id);
  }

  bool _cacheFresh(String providerId) {
    final at = _cacheAt[providerId];
    if (at == null) return false;
    return DateTime.now().difference(at) < ttl;
  }

  bool _sameIds(List<ProviderModelInfo>? a, List<ProviderModelInfo> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _emit() {
    notifyListeners();
    onChanged?.call();
  }

  /// [force] 强制刷新；否则有缓存直接返回，TTL 过期可静默刷新。
  Future<List<ProviderModelInfo>> load({
    bool force = false,
    bool silentRefreshIfStale = true,
    bool Function(ProviderConfig p)? canUse,
  }) async {
    final p = providers.activeProvider;
    if (p == null) return const [];
    if (canUse != null && !canUse(p)) return const [];
    final cached = _cache[p.id];
    if (!force && cached != null && cached.isNotEmpty) {
      if (silentRefreshIfStale && !_cacheFresh(p.id)) {
        unawaited(_fetch(p.id, notifyError: false, silent: true));
      }
      return List.unmodifiable(cached);
    }
    return _fetch(p.id, notifyError: true);
  }

  Future<List<ProviderModelInfo>> _fetch(
    String providerId, {
    required bool notifyError,
    bool silent = false,
  }) async {
    if (!silent) {
      _loading = true;
      if (notifyError) _error = null;
      _emit();
    }
    var shouldNotify = !silent;
    try {
      final list = await providers.listModels(providerId);
      final prev = _cache[providerId];
      final unchanged = _sameIds(prev, list);
      _cache[providerId] = list;
      _cacheAt[providerId] = DateTime.now();
      _error = null;
      if (silent) {
        shouldNotify = !unchanged;
      }
      return List.unmodifiable(list);
    } catch (e) {
      if (notifyError || _cache[providerId] == null) {
        _error = e.toString();
        shouldNotify = true;
      } else if (silent) {
        shouldNotify = false;
      }
      return List.unmodifiable(_cache[providerId] ?? const []);
    } finally {
      if (!silent) {
        _loading = false;
      }
      if (shouldNotify) {
        _emit();
      }
    }
  }
}
