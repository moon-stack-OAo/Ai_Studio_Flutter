import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

const settingsConflictMessage = '本机配置已被其他操作更新，当前草稿已保留。保存时需要确认覆盖；取消可载入最新配置。';

Future<bool> confirmSettingsOverwrite(BuildContext context) =>
    showFluentConfirmDialog(
      context: context,
      title: '覆盖最新配置？',
      message: '此配置已被导入或其他操作更新。继续保存将用当前草稿覆盖最新配置。',
      confirmLabel: '覆盖保存',
      cancelLabel: '继续编辑',
    );
