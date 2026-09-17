import 'dart:async';
import 'dart:io';

/// 子进程宿主抽象（DESIGN §5.11.8 · P6-S）。
///
/// `StdioMcpSession` **必须**经本接口启动进程，便于测试 Fake 与桌面注入。
/// 真正的 [Process.start] 可由 [IoProcessHost]（core 提供，桌面可直接用）
/// 或 `apps/desktop_fluent` 自定义实现注入；mobile **不**注入。
abstract class ProcessHost {
  Future<HostedProcess> start({
    required String command,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
  });
}

/// 已启动的子进程句柄（stdio 管道）。
abstract class HostedProcess {
  /// 标准输入（写入 JSON-RPC 行）。
  IOSink get stdin;

  /// 标准输出字节流。
  Stream<List<int>> get stdout;

  /// 标准错误字节流（日志/诊断；协议主路径读 stdout）。
  Stream<List<int>> get stderr;

  /// 进程退出码。
  Future<int> get exitCode;

  /// 是否仍在运行（尽力而为）。
  bool get isRunning;

  /// 终止进程；返回是否发出信号。
  bool kill();
}

/// 基于 `dart:io` [Process] 的默认实现（桌面可直接注入）。
class IoProcessHost implements ProcessHost {
  const IoProcessHost();

  @override
  Future<HostedProcess> start({
    required String command,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      command,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
      // 合并 PATH 等，便于 `node` / `npx` 一类命令名。
      includeParentEnvironment: true,
      runInShell: false,
    );
    return _IoHostedProcess(process);
  }
}

class _IoHostedProcess implements HostedProcess {
  _IoHostedProcess(this._process);

  final Process _process;
  bool _killed = false;

  @override
  IOSink get stdin => _process.stdin;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool get isRunning => !_killed;

  @override
  bool kill() {
    _killed = true;
    return _process.kill(ProcessSignal.sigterm);
  }
}
