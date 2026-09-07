import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 平台安全存储抽象（OS 凭据库 / Keychain / Keystore 等）。
///
/// 生产用 [FlutterSecureSecretStore]；单元测试用 [MemorySecretStore]。
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<bool> containsKey(String key);
}

/// 基于 [FlutterSecureStorage] 的生产实现。
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                // v10+ 默认 RSA-OAEP + AES-GCM；算法变更时带备份迁移。
                // 注：encryptedSharedPreferences 在 v10+ 已弃用，勿再开启。
                migrateOnAlgorithmChange: true,
                migrateWithBackup: true,
              ),
              // Windows：加密文件 + Credential Manager 中的 AES 密钥；
              // 编译需 VS「C++ ATL」（atlstr.h）。
              wOptions: WindowsOptions(useBackwardCompatibility: false),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);
}

/// 内存实现（单元测试 / 无插件环境）。
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial])
      : _data = Map<String, String>.from(initial ?? const {});

  final Map<String, String> _data;

  @visibleForTesting
  Map<String, String> get debugData => Map.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}
