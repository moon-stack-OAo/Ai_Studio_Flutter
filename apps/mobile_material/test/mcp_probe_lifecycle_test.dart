import 'dart:async';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mobile_material/pages/settings/mcp_edit_sheet.dart';

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
  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    await gate?.future;
    await super.save(snapshot);
  }
}

void main() {
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
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showMcpEditSheet(
                    context: context,
                    repository: repo,
                    sessionFactory: factory,
                    serverId: id,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final button = find.text('测试连接 / 刷新 tools');
      await tester.scrollUntilVisible(
        button,
        350,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
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
