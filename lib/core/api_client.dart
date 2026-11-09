import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'secure_store.dart';

/// Fixed public API key documented in openapi.json (x-api-key).
const _apiKey = 'v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3';

final _rnd = Random.secure();

/// x-message-id: UUIDv4 as url-safe base64 without padding (22 chars).
String newMessageId() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  return base64UrlEncode(b).replaceAll('=', '');
}

class ThinqApiClient {
  ThinqApiClient(this.credentials)
      : _dio = Dio(
          BaseOptions(
            baseUrl: credentials.region.baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: 'application/json',
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll({
            'Authorization': 'Bearer ${credentials.pat}',
            'x-message-id': newMessageId(),
            'x-country': credentials.country,
            'x-client-id': credentials.clientId,
            'x-api-key': _apiKey,
            'x-service-phase': 'OP',
          });
          handler.next(options);
        },
      ),
    );
  }

  final ThinqCredentials credentials;
  final Dio _dio;

  Future<dynamic> get(String path) => _run(() => _dio.get(path));

  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _run(() => _dio.post(path, data: body));

  /// Returns the `response` field of the ThinQ envelope.
  Future<dynamic> _run(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      return data is Map ? data['response'] : data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        throw ThinqException('Token (PAT) inválido ou expirado.',
            statusCode: code);
      }
      if (code != null) {
        throw ThinqException('A LG recusou o comando (erro $code).',
            statusCode: code);
      }
      throw ThinqException('Sem conexão com a LG.');
    }
  }
}
