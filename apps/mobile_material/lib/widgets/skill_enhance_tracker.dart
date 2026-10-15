import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// 记录润色请求使用的技能版本，只维护面板提示状态。
class SkillEnhanceTracker extends ChangeNotifier {
  SkillEnhanceTracker({required this.repository, required PromptDomain domain})
    : target = domain == PromptDomain.image
          ? SkillTarget.image
          : SkillTarget.video {
    repository?.addListener(_onChanged);
  }

  final SkillRepository? repository;
  final SkillTarget target;
  String? _requestFingerprint;
  bool _changed = false;

  bool get changed => _changed;

  /// 结果被丢弃后停止追踪；和 capture 一样，由面板刷新 UI。
  void clear() {
    _requestFingerprint = null;
    _changed = false;
  }

  List<SkillSnapshot> capture() {
    _requestFingerprint = repository?.fingerprintFor(target);
    _changed = false;
    return repository?.snapshotFor(target) ?? const [];
  }

  void _onChanged() {
    if (_requestFingerprint == null) return;
    final next = repository?.fingerprintFor(target) != _requestFingerprint;
    if (next == _changed) return;
    _changed = next;
    notifyListeners();
  }

  @override
  void dispose() {
    repository?.removeListener(_onChanged);
    super.dispose();
  }
}
