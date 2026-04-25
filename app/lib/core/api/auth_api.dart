import 'dart:convert';

import 'api_client.dart';

class LoginInfo {
  final String kdfSaltB64;
  final Map<String, dynamic> kdfParams;
  LoginInfo(this.kdfSaltB64, this.kdfParams);
}

class AuthSession {
  final String token;
  final String userId;
  AuthSession(this.token, this.userId);
}

class AuthApi {
  final ApiClient _api;
  AuthApi(this._api);

  Future<AuthSession> register({
    required String login,
    required String authKeyB64,
    required String kdfSaltB64,
    required Map<String, dynamic> kdfParams,
  }) async {
    final r = await _api.dio.post('/auth/register', data: jsonEncode({
      'login': login,
      'auth_key': authKeyB64,
      'kdf_salt': kdfSaltB64,
      'kdf_params': kdfParams,
    }));
    return AuthSession(r.data['token'] as String, r.data['user_id'] as String);
  }

  Future<LoginInfo> loginInfo(String login) async {
    final r = await _api.dio.post('/auth/login', data: jsonEncode({'login': login}));
    return LoginInfo(
      r.data['kdf_salt'] as String,
      Map<String, dynamic>.from(r.data['kdf_params'] as Map),
    );
  }

  Future<AuthSession> loginVerify({
    required String login,
    required String authKeyB64,
  }) async {
    final r = await _api.dio.post('/auth/login/verify', data: jsonEncode({
      'login': login,
      'auth_key': authKeyB64,
    }));
    return AuthSession(r.data['token'] as String, r.data['user_id'] as String);
  }
}
