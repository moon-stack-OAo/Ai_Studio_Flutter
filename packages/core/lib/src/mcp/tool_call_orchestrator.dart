import 'mcp_client.dart';
import 'mcp_models.dart';
import 'mcp_sanitize.dart';
import 'mcp_tool_policy.dart';

/// CHAT-TOOL-AUTH 授权提示载荷（UI 注入；core 无 Widget）。
class ToolAuthPrompt {
  const ToolAuthPrompt({
    required this.serverId,
    required this.serverDisplayName,
    required this.toolName,
    this.toolTitle,
    this.sideEffect = McpToolSideEffect.unknown,
    this.argumentsSummary,
    this.policyLevel = McpToolPolicyLevel.confirmAlways,
  });

  final String serverId;
  final String serverDisplayName;
  final String toolName;
  final String? toolTitle;
  final McpToolSideEffect sideEffect;
  final String? argumentsSummary;
  final McpToolPolicyLevel policyLevel;
}

/// UI 授权回调：返回 true=允许，false=拒绝。
typedef ToolAuthPrompter = Future<bool> Function(ToolAuthPrompt prompt);

/// 轨迹状态变更（供 UI 刷新 CHAT-TOOL-CALL 气泡）。
typedef ToolCallTraceListener = void Function(ChatToolCallTrace trace);

/// 单次用户发送内的 tool 编排选项。
class ToolCallOrchestratorOptions {
  const ToolCallOrchestratorOptions({
    this.maxRounds = kDefaultMcpMaxToolRounds,
    this.defaultCallTimeout = kDefaultMcpCallTimeout,
    this.serialCalls = true,
  });

  /// 单次用户发送触发的 tool 循环硬上限（§5.11.3）。
  final int maxRounds;

  final Duration defaultCallTimeout;

  /// 同轮多个 tool_calls：默认串行（待决 Q8；并行需另定策略）。
  final bool serialCalls;
}

/// 编排「模型 tool_calls → policy → auth → call → 回灌」的接口。
///
/// **挂载点**：由 [ChatSessionFacade] 注入并在流式结束后若 `hasToolCalls` 调用。
/// 取消应对齐 [GenerationRuntime.abort]：停止中取消进行中的 HTTP call，
/// 并中止后续 tool 循环。
abstract class ToolCallOrchestrator {
  /// 处理一批模型返回的 tool_calls；返回按序结果供回灌 `role=tool`。
  ///
  /// [isCancelled] 通常绑定 generation abort（如 `() => !generation.isCurrent(sid)`）。
  Future<List<McpToolCallResult>> runRound({
    required List<McpToolCallRequest> calls,
    required ToolAuthPrompter prompter,
    ToolCallTraceListener? onTrace,
    bool Function()? isCancelled,
    ToolCallOrchestratorOptions options = const ToolCallOrchestratorOptions(),
  });
}

/// 默认编排器：策略 → 授权 → [McpSession.callTool]（同轮串行，Q8）。
///
/// deny / 用户拒绝：回灌拒绝结果，**不**调用 Server。
class DefaultToolCallOrchestrator implements ToolCallOrchestrator {
  DefaultToolCallOrchestrator({
    required this.resolveSession,
    required this.resolveTool,
    required this.resolveServer,
    this.policyResolver = const McpToolPolicyResolver(),
    McpSessionToolGrants? sessionGrants,
  }) : sessionGrants = sessionGrants ?? McpSessionToolGrants();

  /// 按 serverId 取得已打开的 [McpSession]。
  final McpSession Function(String serverId) resolveSession;

  final McpToolDescriptor Function(String serverId, String toolName)
      resolveTool;

  final McpServerConfig Function(String serverId) resolveServer;

  final McpToolPolicyResolver policyResolver;
  final McpSessionToolGrants sessionGrants;

  @override
  Future<List<McpToolCallResult>> runRound({
    required List<McpToolCallRequest> calls,
    required ToolAuthPrompter prompter,
    ToolCallTraceListener? onTrace,
    bool Function()? isCancelled,
    ToolCallOrchestratorOptions options = const ToolCallOrchestratorOptions(),
  }) async {
    final out = <McpToolCallResult>[];
    var executed = 0;

    for (final call in calls) {
      if (isCancelled?.call() == true) {
        out.add(_cancelled(call));
        continue;
      }
      if (executed >= options.maxRounds) {
        out.add(
          McpToolCallResult(
            toolCallId: call.toolCallId,
            status: McpToolCallStatus.rejected,
            content: '已达本回合工具调用上限（${options.maxRounds}）',
            isError: true,
            errorMessage: 'max_tool_rounds',
          ),
        );
        continue;
      }

      if (call.serverId.trim().isEmpty) {
        final rejected = McpToolCallResult(
          toolCallId: call.toolCallId,
          status: McpToolCallStatus.rejected,
          content: '未找到工具 ${call.toolName} 所属的 MCP Server',
          isError: true,
          errorMessage: 'unknown_tool',
        );
        onTrace?.call(
          ChatToolCallTrace(
            toolCallId: call.toolCallId,
            serverId: '',
            serverDisplayName: '',
            toolName: call.toolName,
            status: McpToolCallStatus.rejected,
            argumentsSummary: call.argumentsSummary,
            errorMessage: rejected.errorMessage,
          ),
        );
        out.add(rejected);
        continue;
      }

      final server = resolveServer(call.serverId);
      final tool = resolveTool(call.serverId, call.toolName);
      final level = policyResolver.resolveEffective(
        server: server,
        tool: tool,
        sessionGrants: sessionGrants,
      );

      var trace = ChatToolCallTrace(
        toolCallId: call.toolCallId,
        serverId: server.id,
        serverDisplayName: server.displayName,
        toolName: tool.name,
        toolTitle: tool.title,
        sideEffect: tool.sideEffect,
        status: McpToolCallStatus.queued,
        argumentsSummary: call.argumentsSummary,
      );
      onTrace?.call(trace);

      if (level == McpToolPolicyLevel.deny) {
        final rejected = McpToolCallResult(
          toolCallId: call.toolCallId,
          status: McpToolCallStatus.rejected,
          content: '策略拒绝调用工具 ${tool.name}',
          isError: true,
          errorMessage: 'policy_deny',
        );
        onTrace?.call(trace.copyWith(status: McpToolCallStatus.rejected));
        out.add(rejected);
        continue;
      }

      if (level == McpToolPolicyLevel.confirmAlways ||
          level == McpToolPolicyLevel.confirmOnce) {
        onTrace?.call(trace.copyWith(status: McpToolCallStatus.pendingAuth));
        final allowed = await prompter(
          ToolAuthPrompt(
            serverId: server.id,
            serverDisplayName: server.displayName,
            toolName: tool.name,
            toolTitle: tool.title,
            sideEffect: tool.sideEffect,
            argumentsSummary: call.argumentsSummary,
            policyLevel: level,
          ),
        );
        if (isCancelled?.call() == true) {
          out.add(_cancelled(call));
          onTrace?.call(trace.copyWith(status: McpToolCallStatus.cancelled));
          continue;
        }
        if (!allowed) {
          final rejected = McpToolCallResult(
            toolCallId: call.toolCallId,
            status: McpToolCallStatus.rejected,
            content: '用户拒绝调用工具 ${tool.name}',
            isError: true,
            errorMessage: 'user_rejected',
          );
          onTrace?.call(trace.copyWith(status: McpToolCallStatus.rejected));
          out.add(rejected);
          continue;
        }
        if (level == McpToolPolicyLevel.confirmOnce) {
          sessionGrants.grant(server.id, tool.name);
        }
      }

      onTrace?.call(trace.copyWith(status: McpToolCallStatus.running));
      final session = resolveSession(call.serverId);
      final timeout = server.callTimeoutSeconds != null
          ? Duration(seconds: server.callTimeoutSeconds!)
          : options.defaultCallTimeout;

      try {
        final result = await session.callTool(
          call,
          timeout: timeout,
          isCancelled: isCancelled,
        );
        executed++;
        onTrace?.call(
          trace.copyWith(
            status: result.status,
            resultSummary: mcpSanitizeSummary(result.content),
            errorMessage: result.errorMessage == null
                ? null
                : mcpSanitizeSummary(result.errorMessage),
          ),
        );
        out.add(result);
      } catch (e) {
        if (isCancelled?.call() == true) {
          out.add(_cancelled(call));
          onTrace?.call(trace.copyWith(status: McpToolCallStatus.cancelled));
          continue;
        }
        final failed = McpToolCallResult(
          toolCallId: call.toolCallId,
          status: McpToolCallStatus.failed,
          content: mcpSanitizeSummary(e.toString()).isEmpty
              ? '工具调用失败'
              : mcpSanitizeSummary(e.toString()),
          isError: true,
          errorMessage: e.runtimeType.toString(),
        );
        onTrace?.call(
          trace.copyWith(
            status: McpToolCallStatus.failed,
            errorMessage: failed.errorMessage,
          ),
        );
        out.add(failed);
      }
    }

    return out;
  }

  static McpToolCallResult _cancelled(McpToolCallRequest call) {
    return McpToolCallResult(
      toolCallId: call.toolCallId,
      status: McpToolCallStatus.cancelled,
      content: '已取消',
      isError: true,
      errorMessage: 'cancelled',
    );
  }
}
