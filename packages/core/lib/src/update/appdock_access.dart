import 'dart:convert';

import 'package:http/http.dart' as http;

import '../provider/secret_store.dart';
import '../security/url_safety.dart';
import 'update_client.dart';
import 'update_models.dart';

/// 安全存储中的 AppDock 访问会话（cookie 值）。
const String kAppDockAccessSessionKey = 'core.update.appdock_access_session';

/// 检查更新时发现需要访问口令。
const String kUpdateAccessRequiredMessage = '需要访问口令才能检查更新';

/// AppDock 口令会话：解锁、持久化、给清单与下载请求带 cookie。
class AppDockAccessSession {
  AppDockAccessSession({
    SecretStore? store,
    this.baseUrl = kAppDockBaseUrl,
    this.slug = kAppDockAppSlug,
    this.timeout = const Duration(seconds: 20),
    http.Client? client,
  })  : _store = store ?? FlutterSecureSecretStore(),
        _ownedClient = client == null,
        _client = client ?? http.Client();

  final SecretStore _store;
  final String baseUrl;
  final String slug;
  final Duration timeout;
  final http.Client _client;
  final bool _ownedClient;

  String? _cookie;

  /// 已加载且非空时为 true。
  bool get hasSession => (_cookie ?? '').trim().isNotEmpty;

  /// 从安全存储读出已保存的会话。
  Future<void> load() async {
    _cookie = (await _store.read(kAppDockAccessSessionKey))?.trim();
    if (_cookie != null && _cookie!.isEmpty) _cookie = null;
  }

  /// 当前请求头；无会话时为空。
  Map<String, String> get headers {
    final cookie = _cookie;
    if (cookie == null || cookie.isEmpty) return const {};
    return {'Cookie': 'access_session=$cookie'};
  }

  /// 用口令换会话并写入安全存储。失败抛 [UpdateException]，不落盘。
  Future<void> unlock(String accessCode) async {
    final code = accessCode.trim();
    if (code.isEmpty) {
      throw const UpdateException('请输入访问口令');
    }
    final uri = Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
      '/api/v1/public/apps/${Uri.encodeComponent(slug)}/unlock',
    );
    try {
      assertSafeFetchUrl(uri);
    } on UrlSafetyException catch (e) {
      throw UpdateException(e.message);
    }

    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'User-Agent': 'AiStudio-Flutter-Updater/1.0',
            },
            body: jsonEncode({'accessCode': code}),
          )
          .timeout(timeout);
    } catch (e) {
      throw UpdateException(friendlyUpdateNetworkError(e));
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UpdateException('口令无效或已失效');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw UpdateException('解锁失败：HTTP ${response.statusCode}');
    }

    final cookie = _sessionCookie(response);
    if (cookie == null || cookie.isEmpty) {
      throw const UpdateException('解锁成功但未返回访问会话');
    }
    _cookie = cookie;
    await _store.write(kAppDockAccessSessionKey, cookie);
  }

  /// 清除内存与安全存储中的会话。
  Future<void> clear() async {
    _cookie = null;
    await _store.delete(kAppDockAccessSessionKey);
  }

  void close() {
    if (_ownedClient) _client.close();
  }

  String? _sessionCookie(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'(?:^|,\s*)access_session=([^;,\s]+)').firstMatch(raw);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return Uri.decodeComponent(value);
  }
}

/// 响应是否表示 AppDock 需要访问口令。
bool updateResponseNeedsAccess(int statusCode, List<int> bodyBytes) {
  if (statusCode != 401 && statusCode != 403) return false;
  final text = _decodeLoose(bodyBytes).toLowerCase();
  return text.contains('password_required') ||
      text.contains('需要访问口令') ||
      text.contains('login_required') ||
      text.contains('unauthorized') ||
      text.contains('forbidden') ||
      text.isEmpty;
}

String _decodeLoose(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}
