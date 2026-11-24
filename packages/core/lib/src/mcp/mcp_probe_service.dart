import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_sanitize.dart';
import 'mcp_server_repository.dart';

/// A result is displayable only when its metadata was durably saved and is
/// still current. Stale operations never resurrect or overwrite a server.
class McpPersistedProbeResult {
  const McpPersistedProbeResult({required this.result, required this.applied});

  final McpProbeResult result;
  final bool applied;
}

/// Shared probe + persist lifecycle, independent of any settings widget.
class McpProbeService {
  const McpProbeService({
    required this.repository,
    required this.sessionFactory,
  });

  final McpServerRepository repository;
  final McpSessionFactory sessionFactory;

  Future<McpPersistedProbeResult> probe(String serverId) async {
    final server = repository.findById(serverId);
    final ticket = repository.beginProbe(serverId);
    if (server == null || ticket == null) {
      return McpPersistedProbeResult(
        result: McpProbeResult.failure('Server 已不存在'),
        applied: false,
      );
    }
    final started = await repository.persistProbe(
      serverId,
      ticket,
      status: McpProbeStatus.probing,
    );
    if (!started) {
      return McpPersistedProbeResult(
        result: McpProbeResult.failure('配置已变更，探测结果已忽略'),
        applied: false,
      );
    }
    McpSession? session;
    late McpProbeResult result;
    try {
      session = sessionFactory.create(server);
      result = await session.probe();
    } catch (e) {
      result = McpProbeResult.failure(
        mcpSanitizeSummary(e.toString(), maxLen: 200),
      );
    } finally {
      try {
        session?.close();
      } catch (_) {
        // Closing is best effort; never skip persisting the probe outcome.
      }
    }
    final applied = await repository.persistProbe(
      serverId,
      ticket,
      status: result.ok ? McpProbeStatus.ready : McpProbeStatus.error,
      tools: result.ok ? result.tools ?? const [] : null,
      atMs: result.atMs,
      error: result.ok
          ? null
          : mcpSanitizeSummary(result.errorMessage ?? '探测失败', maxLen: 200),
    );
    return McpPersistedProbeResult(result: result, applied: applied);
  }
}
