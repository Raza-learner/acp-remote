import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mcp_server.dart';

class PreferencesService {
  static const _keyPairingCode = 'pairing_code';
  static const _keyAuthToken = 'auth_token';
  static const _keyRelayUrl = 'relay_url';
  static const _keyDeviceName = 'device_name';
  static const _keyDefaultCwd = 'default_cwd';
  static const _keyThemeMode = 'theme_mode';
  static const _keyDeletedIds = 'deleted_session_ids';
  static const _keyMcpServers = 'mcp_servers';
  static const _keyConfigChoices = 'config_choices';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  String? getPairingCode() => _prefs.getString(_keyPairingCode);
  Future<void> setPairingCode(String code) =>
      _prefs.setString(_keyPairingCode, code);
  Future<void> clearPairingCode() => _prefs.remove(_keyPairingCode);

  String? getAuthToken() => _prefs.getString(_keyAuthToken);
  Future<void> setAuthToken(String token) =>
      _prefs.setString(_keyAuthToken, token);
  Future<void> clearAuthToken() => _prefs.remove(_keyAuthToken);

  String? getRelayUrl() => _prefs.getString(_keyRelayUrl);
  Future<void> setRelayUrl(String url) =>
      _prefs.setString(_keyRelayUrl, url);
  Future<void> clearRelayUrl() => _prefs.remove(_keyRelayUrl);

  String? getDeviceName() => _prefs.getString(_keyDeviceName);
  Future<void> setDeviceName(String name) =>
      _prefs.setString(_keyDeviceName, name);
  Future<void> clearDeviceName() => _prefs.remove(_keyDeviceName);

  String? getDefaultCwd() => _prefs.getString(_keyDefaultCwd);
  Future<void> setDefaultCwd(String cwd) =>
      _prefs.setString(_keyDefaultCwd, cwd);

  String getThemeMode() => _prefs.getString(_keyThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString(_keyThemeMode, mode);

  List<String> getDeletedSessionIds() {
    final raw = _prefs.getStringList(_keyDeletedIds);
    return raw ?? [];
  }

  Future<void> setDeletedSessionIds(List<String> ids) async {
    await _prefs.setStringList(_keyDeletedIds, ids);
  }

  List<McpServer> getMcpServers() {
    final raw = _prefs.getString(_keyMcpServers);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => McpServer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setMcpServers(List<McpServer> servers) async {
    final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
    await _prefs.setString(_keyMcpServers, raw);
  }

  /// Per-agent config choices (e.g. selected model), as
  /// `{agentId: {configId: value}}`. Used to re-apply the user's last
  /// model/mode pick whenever the agent reports fresh (default) configs.
  Map<String, String> getConfigChoices(String agentId) {
    final raw = _prefs.getString(_keyConfigChoices);
    if (raw == null) return {};
    try {
      final all = jsonDecode(raw) as Map<String, dynamic>;
      final agent = all[agentId] as Map<String, dynamic>?;
      if (agent == null) return {};
      return agent.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> setConfigChoice(
      String agentId, String configId, String value) async {
    Map<String, dynamic> all = {};
    final raw = _prefs.getString(_keyConfigChoices);
    if (raw != null) {
      try {
        all = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    final agent =
        Map<String, dynamic>.from(all[agentId] as Map? ?? <String, dynamic>{});
    agent[configId] = value;
    all[agentId] = agent;
    await _prefs.setString(_keyConfigChoices, jsonEncode(all));
  }

  Future<void> clearAll() async {
    await clearPairingCode();
    await clearAuthToken();
    await clearRelayUrl();
    await clearDeviceName();
    await _prefs.remove(_keyMcpServers);
  }
}
