import 'package:core/core.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// F-SessionOverrides：本会话参数覆盖（CHAT-OVERRIDE）。
Future<void> showSessionOverridesDialog({
  required BuildContext context,
  required ChatSession session,
  required ChatDefaults defaults,
  required Future<void> Function(ChatOverrides overrides) onSave,
}) async {
  final systemCtrl = TextEditingController(
    text: session.overrides.systemPrompt ?? '',
  );
  var temperature =
      session.overrides.temperature ?? defaults.temperature;
  var overrideSystem = session.overrides.systemPrompt != null;
  var overrideTemp = session.overrides.temperature != null;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final tokens = fluentTokensOf(ctx);
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return ContentDialog(
            title: const Text('会话参数'),
            // Fluent 会话参数 Dialog 建议宽 ≈480；装饰走全局 dialogTheme
            constraints: const BoxConstraints(
              maxWidth: 480,
              maxHeight: 560,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '仅影响当前会话；留空/关闭覆盖则回退全局默认。',
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Checkbox(
                    checked: overrideSystem,
                    onChanged: (v) {
                      setLocal(() {
                        overrideSystem = v == true;
                        if (!overrideSystem) {
                          systemCtrl.text = '';
                        } else if (systemCtrl.text.isEmpty) {
                          systemCtrl.text = defaults.systemPrompt;
                        }
                      });
                    },
                    content: Text(
                      '覆盖系统提示',
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextBox(
                    controller: systemCtrl,
                    maxLines: 4,
                    enabled: overrideSystem,
                    placeholder: defaults.systemPrompt.isEmpty
                        ? '留空则不传 system'
                        : defaults.systemPrompt,
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 14),
                  Checkbox(
                    checked: overrideTemp,
                    onChanged: (v) {
                      setLocal(() {
                        overrideTemp = v == true;
                        if (!overrideTemp) {
                          temperature = defaults.temperature;
                        }
                      });
                    },
                    content: Text(
                      '覆盖温度  ${temperature.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: temperature,
                    min: 0,
                    max: 2,
                    divisions: 40,
                    label: temperature.toStringAsFixed(2),
                    onChanged: overrideTemp
                        ? (v) {
                            setLocal(() {
                              temperature =
                                  double.parse(v.toStringAsFixed(2));
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '全局默认温度 ${defaults.temperature.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.inkMuted,
                      fontFamily: tokens.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Button(
                onPressed: () async {
                  await onSave(const ChatOverrides());
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('清除覆盖'),
              ),
              Button(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final overrides = ChatOverrides(
                    systemPrompt: overrideSystem
                        ? systemCtrl.text
                        : null,
                    temperature: overrideTemp ? temperature : null,
                  );
                  await onSave(overrides);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  systemCtrl.dispose();
}
