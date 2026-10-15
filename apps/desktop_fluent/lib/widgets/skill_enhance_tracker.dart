import 'package:core/core.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 只跟踪桌面润色结果是否过期；快照和指纹均来自 core。
class SkillEnhanceTracker extends ChangeNotifier {
  SkillEnhanceTracker(this._repository, this._domain) {
    _repository?.addListener(_changed);
  }

  SkillRepository? _repository;
  PromptDomain _domain;
  String? _captured;

  SkillTarget get _target =>
      _domain == PromptDomain.image ? SkillTarget.image : SkillTarget.video;

  bool get changed =>
      _captured != null &&
      _captured != (_repository?.fingerprintFor(_target) ?? '');

  List<SkillSnapshot> capture() {
    _captured = _repository?.fingerprintFor(_target) ?? '';
    return _repository?.snapshotFor(_target) ?? const [];
  }

  void update(SkillRepository? repository, PromptDomain domain) {
    if (_repository != repository) {
      _repository?.removeListener(_changed);
      _repository = repository;
      _repository?.addListener(_changed);
    }
    if (_domain != domain) _captured = null;
    _domain = domain;
  }

  void clear() => _captured = null;

  void _changed() => notifyListeners();

  @override
  void dispose() {
    _repository?.removeListener(_changed);
    super.dispose();
  }
}

class SkillEnhanceNotice extends StatelessWidget {
  const SkillEnhanceNotice({super.key, required this.tracker});
  final SkillEnhanceTracker tracker;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tracker,
    builder: (context, _) => tracker.changed
        ? const Padding(
            padding: EdgeInsets.only(top: 8),
            child: InfoBar(
              title: Text('技能已变更，建议重新润色'),
              severity: InfoBarSeverity.warning,
            ),
          )
        : const SizedBox.shrink(),
  );
}
