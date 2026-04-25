import 'package:dio/dio.dart';

import '../storage/secure_storage.dart';

class ApiClient {
  final SecureStore _store;
  late final Dio _dio;

  ApiClient(this._store) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        options.baseUrl = await _store.getServerUrl();
        final jwt = await _store.getJwt();
        if (jwt != null && jwt.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $jwt';
        }
        handler.next(options);
      },
    ));
  }

  Dio get dio => _dio;
}
