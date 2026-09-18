import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐藏入口（设置「实验室」）解锁状态。
///
/// SharedPreferences：
/// - `core.hidden_portal.unlocked_at.v1` → int（解锁时刻 ms，缺省未解锁）
/// - 兼容旧键 `core.hidden_portal.unlocked.v1`：true 时迁移为「此刻」解锁
///
/// 解锁后 [ttl] 到期自动隐藏；[lock] / 再次连点可立即隐藏。
class HiddenPortalPrefs extends ChangeNotifier {
  HiddenPortalPrefs({
    SharedPreferences? prefs,
    this.clock = _defaultClock,
    this.ttl = const Duration(days: 7),
  }) : _prefsOverride = prefs;

  static const unlockedKey = 'core.hidden_portal.unlocked.v1';
  static const unlockedAtKey = 'core.hidden_portal.unlocked_at.v1';

  static DateTime _defaultClock() => DateTime.now();

  final SharedPreferences? _prefsOverride;
  final DateTime Function() clock;
  final Duration ttl;

  SharedPreferences? _prefs;

  bool _loaded = false;
  int? _unlockedAtMs;

  bool get isLoaded => _loaded;

  /// 当前是否在有效解锁窗口内。
  bool get unlocked {
    final at = _unlockedAtMs;
    if (at == null) return false;
    final unlockedAt = DateTime.fromMillisecondsSinceEpoch(at);
    return clock().difference(unlockedAt) < ttl;
  }

  DateTime? get unlockedAt {
    final at = _unlockedAtMs;
    if (at == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(at);
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  Future<void> load() async {
    final prefs = await _ensurePrefs();
    var at = prefs.getInt(unlockedAtKey);
    if (at == null) {
      final legacy = prefs.getBool(unlockedKey);
      if (legacy == true) {
        at = clock().millisecondsSinceEpoch;
        await prefs.setInt(unlockedAtKey, at);
        await prefs.remove(unlockedKey);
      } else if (legacy == false) {
        await prefs.remove(unlockedKey);
      }
    }

    if (at != null) {
      final unlockedAt = DateTime.fromMillisecondsSinceEpoch(at);
      if (clock().difference(unlockedAt) >= ttl) {
        await prefs.remove(unlockedAtKey);
        await prefs.remove(unlockedKey);
        at = null;
      }
    }

    _unlockedAtMs = at;
    _loaded = true;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) {
      await _expireIfNeeded();
      return;
    }
    await load();
  }

  Future<void> _expireIfNeeded() async {
    if (!unlocked && _unlockedAtMs != null) {
      final prefs = await _ensurePrefs();
      await prefs.remove(unlockedAtKey);
      await prefs.remove(unlockedKey);
      _unlockedAtMs = null;
      notifyListeners();
    }
  }

  /// 解锁并刷新有效期（从当前时刻起 [ttl]）。
  Future<void> unlock() async {
    await ensureLoaded();
    final prefs = await _ensurePrefs();
    final at = clock().millisecondsSinceEpoch;
    await prefs.setInt(unlockedAtKey, at);
    await prefs.remove(unlockedKey);
    _unlockedAtMs = at;
    notifyListeners();
  }

  Future<void> lock() async {
    await ensureLoaded();
    if (_unlockedAtMs == null && !unlocked) return;
    final prefs = await _ensurePrefs();
    await prefs.remove(unlockedAtKey);
    await prefs.remove(unlockedKey);
    _unlockedAtMs = null;
    notifyListeners();
  }

  /// 未解锁 → 解锁；已解锁 → 隐藏。返回操作后是否处于解锁态。
  Future<bool> toggle() async {
    await ensureLoaded();
    if (unlocked) {
      await lock();
      return false;
    }
    await unlock();
    return true;
  }
}
