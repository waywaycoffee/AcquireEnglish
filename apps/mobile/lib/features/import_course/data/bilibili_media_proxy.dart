import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Localhost reverse proxy so media_kit never has to resolve bilibili CDN DNS.
class BilibiliMediaProxy {
  BilibiliMediaProxy._();

  static HttpServer? _server;
  static Dio? _dio;
  static String? _upstream;
  static Map<String, String> _headers = <String, String>{};
  static Future<void>? _bindFuture;

  static Future<String> serve({
    required String upstreamUrl,
    required Map<String, String> headers,
    required Dio dio,
  }) async {
    _upstream = upstreamUrl;
    _headers = headers;
    _dio = dio;
    await _ensureServer();
    final int port = _server!.port;
    return 'http://127.0.0.1:$port/media.mp4';
  }

  static Future<void> _ensureServer() {
    if (_server != null) {
      return Future<void>.value();
    }
    return _bindFuture ??= () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      server.listen(_handleRequest, onError: (_) {});
      _server = server;
    }();
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final HttpResponse response = request.response;
    final String? upstream = _upstream;
    final Dio? dio = _dio;
    if (upstream == null || dio == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      response.write('bilibili proxy not ready');
      await response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    try {
      final Map<String, dynamic> headers = <String, dynamic>{..._headers};
      final String? range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        headers[HttpHeaders.rangeHeader] = range;
      }

      final Response<ResponseBody> upstreamRes = await dio.get<ResponseBody>(
        upstream,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (int? code) =>
              code != null && code >= 200 && code < 500,
          receiveTimeout: const Duration(minutes: 15),
        ),
      );

      final int status = upstreamRes.statusCode ?? HttpStatus.ok;
      response.statusCode = status;
      upstreamRes.headers.forEach((String name, List<String> values) {
        final String lower = name.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'content-range' ||
            lower == 'accept-ranges' ||
            lower == 'etag' ||
            lower == 'last-modified') {
          response.headers.set(name, values);
        }
      });
      if (response.headers.contentType == null) {
        response.headers.contentType = ContentType('video', 'mp4');
      }

      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      final ResponseBody? body = upstreamRes.data;
      if (body == null) {
        await response.close();
        return;
      }
      await response.addStream(body.stream);
      await response.close();
    } catch (e) {
      try {
        response.statusCode = HttpStatus.badGateway;
        response.write('bilibili proxy error: $e');
        await response.close();
      } catch (_) {}
    }
  }
}
