import 'package:core/core.dart';
import 'package:design_material/design_material.dart';
import 'package:flutter/material.dart';

/// M-SessionOverrides：本会话参数覆盖 BottomSheet（CHAT-OVERRIDE）。
Future<void> showSessionOverridesSheet({
  required BuildContext context,
  required ChatSession session,
  required ChatDefaults defaults,
  required Future<void> Function(ChatOverrides overrides) onSave,
}) async {
  final systemCtrl = TextEditingController(
    text: session.overrides.systemPrompt ?? '',
  );
  var temperature = session.overrides.temperature ?? defaults.temperature;
  var overrideSystem = session.overrides.systemPrompt != null;
  var overrideTemp = session.overrides.temperature != null;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final tokens = materialTokensOf(ctx);
      final media = MediaQuery.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '会话参数',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '仅影响当前会话；关闭覆盖则回退全局默认。',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '覆盖系统提示',
                        style: TextStyle(
                          fontSize: 14,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      value: overrideSystem,
                      onChanged: (v) {
                        setLocal(() {
                          overrideSystem = v;
                          if (!overrideSystem) {
                            systemCtrl.text = '';
                          } else if (systemCtrl.text.isEmpty) {
                            systemCtrl.text = defaults.systemPrompt;
                          }
                        });
                      },
                    ),
                    TextField(
                      controller: systemCtrl,
                      enabled: overrideSystem,
                      maxLines: 4,
                      style: TextStyle(
                        fontSize: 14,
                        color: tokens.ink,
                        fontFamily: tokens.fontFamily,
                      ),
                      decoration: InputDecoration(
                        hintText: defaults.systemPrompt.isEmpty
                            ? '留空则不传 system'
                            : defaults.systemPrompt,
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '覆盖温度  ${temperature.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: tokens.ink,
                          fontFamily: tokens.fontFamily,
                        ),
                      ),
                      value: overrideTemp,
                      onChanged: (v) {
                        setLocal(() {
                          overrideTemp = v;
                          if (!overrideTemp) {
                            temperature = defaults.temperature;
                          }
                        });
                      },
                    ),
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
                    Text(
                      '全局默认温度 ${defaults.temperature.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.inkMuted,
                        fontFamily: tokens.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            await onSave(const ChatOverrides());
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                          child: const Text('清除覆盖'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () async {
                            final overrides = ChatOverrides(
                              systemPrompt:
                                  overrideSystem ? systemCtrl.text : null,
                              temperature: overrideTemp ? temperature : null,
                            );
                            await onSave(overrides);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  systemCtrl.dispose();
}
