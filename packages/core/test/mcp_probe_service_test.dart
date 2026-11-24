import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session implements McpSession {
  _Session(this.server);
  @override
  final McpServerConfig server;
  final result = Completer<McpProbeResult>();
  int closes = 0;
  bool failClose = false;
  @override
  Future<McpProbeResult> probe({Duration? timeout}) => result.future;
  @override
  void close() {
    closes++;
    if (failClose) throw StateError('close');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Factory implements McpSessionFactory {
  final sessions = <_Session>[];
  bool failCreate = false;
  @override
  McpSession create(
    McpServerConfig server, {
    McpAuthProvider? auth,
    ProcessHost? processHost,
  }) {
    if (failCreate) throw StateError('create');
    final session = _Session(server);
    sessions.add(session);
    return session;
  }
}

class _Storage extends MemoryMcpServerStorage {
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<void> save(McpServerStoreSnapshot snapshot) async {
    entered?.complete();
    entered = null;
    await gate?.future;
    if (fail) throw StateError('storage');
    await super.save(snapshot);
  }
}

class _Secrets extends MemorySecretStore {
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<void> delete(String key) async {
    entered?.complete();
    entered = null;
    await gate?.future;
    await super.delete(key);
  }
}

const _ok = McpProbeResult(
  ok: true,
  atMs: 42,
  tools: [McpToolDescriptor(name: 'biz.query')],
);
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Storage storage;
  late McpServerRepository repo;
  late _Factory factory;
  late String id;
  late McpProbeService service;
  setUp(() async {
    storage = _Storage();
    repo = McpServerRepository(
      storage: storage,
      secretStore: MemorySecretStore(),
    );
    await repo.load();
    id = await repo.add(displayName: 'Biz', baseUrl: 'https://example.com/mcp');
    await repo.waitForPersist();
    factory = _Factory();
    service = McpProbeService(repository: repo, sessionFactory: factory);
  });
  tearDown(() => repo.dispose());

  test('delayed result persists without a UI and closes once', () async {
    final pending = service.probe(id);
    await _flush();
    expect(repo.findById(id)!.probeStatus, McpProbeStatus.probing);
    factory.sessions.single.result.complete(_ok);
    expect((await pending).applied, isTrue);
    expect(
      (await storage.load()).servers.single.probeStatus,
      McpProbeStatus.ready,
    );
    expect(repo.findById(id)!.lastProbeAtMs, 42);
    expect(
      (await storage.load()).servers.single.toolsCache.single.name,
      'biz.query',
    );
    expect(factory.sessions.single.closes, 1);
  });

  for (final mutation in [
    'delete',
    'url',
    'revert',
    'policy',
    'secret',
    'replace',
  ]) {
    test('late result ignored after $mutation', () async {
      final pending = service.probe(id);
      await _flush();
      final original = repo.findById(id)!;
      switch (mutation) {
        case 'delete':
          await repo.delete(id);
        case 'url':
          await repo.update(
            original.copyWith(baseUrl: 'https://other.example/mcp'),
          );
        case 'revert':
          await repo.update(
            original.copyWith(baseUrl: 'https://other.example/mcp'),
          );
          await repo.update(original);
        case 'policy':
          await repo.setDefaultToolPolicy(id, McpToolPolicyLevel.deny);
        case 'secret':
          await repo.writeBearerSecret(id, 'private-token');
        case 'replace':
          await repo.replaceAll([original]);
      }
      factory.sessions.single.result.complete(_ok);
      expect((await pending).applied, isFalse);
      expect(repo.findById(id)?.probeStatus, isNot(McpProbeStatus.ready));
      expect(factory.sessions.single.closes, 1);
    });
  }

  test('newer probe wins across service instances', () async {
    final old = service.probe(id);
    await _flush();
    final newer = McpProbeService(
      repository: repo,
      sessionFactory: factory,
    ).probe(id);
    await _flush();
    factory.sessions.last.result.complete(
      McpProbeResult.failure('new failure'),
    );
    expect((await newer).applied, isTrue);
    factory.sessions.first.result.complete(_ok);
    expect((await old).applied, isFalse);
    expect(repo.findById(id)!.lastError, 'new failure');
  });

  test('probe exception and close exception still persist error', () async {
    final pending = service.probe(id);
    await _flush();
    factory.sessions.single.failClose = true;
    factory.sessions.single.result.completeError(StateError('probe'));
    expect((await pending).result.ok, isFalse);
    expect(repo.findById(id)!.probeStatus, McpProbeStatus.error);
    expect(factory.sessions.single.closes, 1);
  });

  test('factory failure persists error', () async {
    factory.failCreate = true;
    expect((await service.probe(id)).result.ok, isFalse);
    expect(repo.findById(id)!.probeStatus, McpProbeStatus.error);
  });

  test(
    'completion storage failure is not success and queue recovers',
    () async {
      final pending = service.probe(id);
      await _flush();
      storage.fail = true;
      factory.sessions.single.result.complete(_ok);
      await expectLater(pending, throwsStateError);
      expect(repo.findById(id)!.probeStatus, McpProbeStatus.error);
      expect(factory.sessions.single.closes, 1);
      storage.fail = false;
      final retry = service.probe(id);
      await _flush();
      factory.sessions.last.result.complete(_ok);
      expect((await retry).applied, isTrue);
    },
  );

  test(
    'result is not reported applied if configuration changes during save',
    () async {
      final pending = service.probe(id);
      await _flush();
      storage.gate = Completer<void>();
      final entered = storage.entered = Completer<void>();
      factory.sessions.single.result.complete(_ok);
      await entered.future;
      await repo.update(
        repo.findById(id)!.copyWith(baseUrl: 'https://new.example/mcp'),
      );
      storage.gate!.complete();
      expect((await pending).applied, isFalse);
      await repo.waitForPersist();
      expect(
        (await storage.load()).servers.single.baseUrl,
        'https://new.example/mcp',
      );
    },
  );

  for (final operation in [
    'delete',
    'clearBearer',
    'clearAllSecrets',
    'clearAllServers',
  ]) {
    test('probe rejected while $operation awaits secret deletion', () async {
      final secrets = _Secrets();
      final guarded = McpServerRepository(
        storage: storage,
        secretStore: secrets,
      );
      await guarded.load();
      final guardedId = await guarded.add(
        displayName: 'Guarded',
        baseUrl: 'https://example.com/mcp',
        authKind: McpAuthKind.bearer,
        bearerToken: 'token',
      );
      await guarded.waitForPersist();
      secrets.gate = Completer<void>();
      final entered = secrets.entered = Completer<void>();
      final mutation = switch (operation) {
        'delete' => guarded.delete(guardedId),
        'clearBearer' => guarded.clearBearerSecret(guardedId),
        'clearAllSecrets' => guarded.clearAllSecrets(),
        _ => guarded.clearAllServers(),
      };
      await entered.future;
      final blocked = await McpProbeService(
        repository: guarded,
        sessionFactory: factory,
      ).probe(guardedId);
      expect(blocked.applied, isFalse);
      expect(factory.sessions, isEmpty);
      secrets.gate!.complete();
      await mutation;
      expect(
        guarded.findById(guardedId)?.probeStatus,
        isNot(McpProbeStatus.ready),
      );
      guarded.dispose();
    });
  }

  test(
    'probe rejected while delete waits on a delayed storage write',
    () async {
      storage.gate = Completer<void>();
      final entered = storage.entered = Completer<void>();
      await repo.update(repo.findById(id)!.copyWith(displayName: 'Pending'));
      await entered.future;
      final deletion = repo.delete(id);
      expect((await service.probe(id)).applied, isFalse);
      expect(factory.sessions, isEmpty);
      storage.gate!.complete();
      await deletion;
      expect(repo.findById(id), isNull);
    },
  );

  for (final sameServer in [true, false]) {
    test(
      'save race preserves ${sameServer ? 'same server policy' : 'other server CRUD'}',
      () async {
        final pending = service.probe(id);
        await _flush();
        storage.gate = Completer<void>();
        final entered = storage.entered = Completer<void>();
        factory.sessions.single.result.complete(_ok);
        await entered.future;
        if (sameServer) {
          await repo.setDefaultToolPolicy(id, McpToolPolicyLevel.deny);
        } else {
          await repo.add(
            displayName: 'Other',
            baseUrl: 'https://other.example/mcp',
          );
        }
        storage.gate!.complete();
        expect((await pending).applied, !sameServer);
        await repo.waitForPersist();
        final saved = await storage.load();
        if (sameServer) {
          expect(
            saved.servers.single.defaultToolPolicy,
            McpToolPolicyLevel.deny,
          );
          expect(saved.servers.single.probeStatus, isNot(McpProbeStatus.ready));
        } else {
          expect(saved.servers, hasLength(2));
          expect(saved.servers.first.probeStatus, McpProbeStatus.ready);
        }
      },
    );
  }

  test('initial storage failure never starts a session', () async {
    storage.fail = true;
    await expectLater(service.probe(id), throwsStateError);
    expect(factory.sessions, isEmpty);
    expect(repo.findById(id)!.probeStatus, McpProbeStatus.error);
  });

  test(
    'probe preserves approved stdio environment and authorization',
    () async {
      final stdioId = await repo.add(
        displayName: 'Local',
        transport: McpTransport.stdio,
        command: 'node',
        args: ['server.js'],
        env: {'SECRET': 'env-value'},
        cwd: 'D:/fixture',
        stdioConfirmed: true,
      );
      final before = repo.findById(stdioId)!;
      final pending = service.probe(stdioId);
      await _flush();
      factory.sessions.single.result.complete(_ok);
      expect((await pending).applied, isTrue);
      final after = repo.findById(stdioId)!;
      expect(after.env, before.env);
      expect(after.stdioApproval, before.stdioApproval);
      expect(after.isStdioApproved, isTrue);
      expect(
        mcpAuthorizationFingerprint(after),
        mcpAuthorizationFingerprint(before),
      );
    },
  );

  test('probe patch preserves bearer and policy', () async {
    await repo.writeBearerSecret(id, 'private-token');
    await repo.setDefaultToolPolicy(id, McpToolPolicyLevel.deny);
    final before = repo.findById(id)!;
    final pending = service.probe(id);
    await _flush();
    factory.sessions.single.result.complete(_ok);
    await pending;
    expect(await repo.readBearerSecret(id), 'private-token');
    expect(
      mcpAuthorizationFingerprint(repo.findById(id)!),
      mcpAuthorizationFingerprint(before),
    );
    expect(repo.secretRevision(id), 1);
  });
}
