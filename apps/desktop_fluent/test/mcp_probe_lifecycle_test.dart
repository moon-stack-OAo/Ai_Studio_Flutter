import 'dart:async';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:design_fluent/design_fluent.dart';
import 'package:desktop_fluent/pages/settings/settings_mcp_page.dart';

class _Factory implements McpSessionFactory {
  final session = _Session();
  @override
  McpSession create(
    McpServerConfig server, {
    McpAuthProvider? auth,
    ProcessHost? processHost,
  }) => session;
}

class _Session implements McpSession {
  final result = Completer<McpProbeResult>();
  int closes = 0;
  @override
  Future<McpProbeResult> probe({Duration? timeout}) => result.future;
  @override
  void close() {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage extends MemoryMcpServerStorage {
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    await gate?.future;
    if (fail) throw StateError('storage failed');
    await super.save(snapshot);
  }
}

void main() {
  testWidgets('old probe storage error is not shown on another server', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _Storage();
    final repo = McpServerRepository(storage: storage);
    await repo.load();
    await repo.add(
      displayName: 'First fixture',
      baseUrl: 'https://example.com/mcp',
    );
    await repo.add(
      displayName: 'Other fixture',
      baseUrl: 'https://other.example/mcp',
    );
    await repo.waitForPersist();
    final factory = _Factory();
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentLightTheme(),
        home: SettingsMcpPage(repository: repo, sessionFactory: factory),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.text('测试连接 / 刷新 tools');
    await tester.scrollUntilVisible(
      button,
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Other fixture').first);
    await tester.pumpAndSettle();
    storage.fail = true;
    factory.session.result.complete(const McpProbeResult(ok: true, atMs: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('探测状态保存失败，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });

  for (final duringSave in [false, true]) {
    testWidgets('probe survives UI disposal (during save: $duringSave)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = _Storage();
      final repo = McpServerRepository(storage: storage);
      await repo.load();
      final id = await repo.add(
        displayName: 'Probe fixture',
        baseUrl: 'https://example.com/mcp',
      );
      await repo.waitForPersist();
      final factory = _Factory();
      await tester.pumpWidget(
        FluentApp(
          theme: buildFluentLightTheme(),
          home: SettingsMcpPage(repository: repo, sessionFactory: factory),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('测试连接 / 刷新 tools');
      await tester.scrollUntilVisible(
        button,
        350,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.findById(id)!.probeStatus, McpProbeStatus.probing);
      if (duringSave) {
        storage.gate = Completer<void>();
        factory.session.result.complete(
          const McpProbeResult(ok: true, atMs: 1),
        );
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      if (duringSave) {
        storage.gate!.complete();
      } else {
        factory.session.result.complete(
          const McpProbeResult(ok: true, atMs: 1),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await repo.waitForPersist();
      expect(repo.findById(id)!.probeStatus, McpProbeStatus.ready);
      expect(
        (await storage.load()).servers.single.probeStatus,
        McpProbeStatus.ready,
      );
      expect(factory.session.closes, 1);
      expect(tester.takeException(), isNull);
      repo.dispose();
    });
  }
}
