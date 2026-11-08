import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repository/network_repository.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/login_response.dart';
import '../domain/register_response.dart';

part 'authentication_repository.g.dart';

/// An abstract class that defines the authentication methods.
abstract class AuthenticationRepository {
  /// Authenticates a user with the given [email] and [password].
  Future<LoginResponse> login(String email, String password);

  /// Registers a new user with the given [email] and [password].
  Future<RegisterResponse> register(String email, String password);
}

/// AcquireEnglish API auth (JWT access_token).
class HttpAuthRepository implements AuthenticationRepository {
  HttpAuthRepository(this._api, this._setToken);

  final AcquireApiClient _api;
  final void Function(String) _setToken;

  @override
  Future<LoginResponse> login(String email, String password) async {
    try {
      final AcquireTokenResult result = await _api.login(
        email: email,
        password: password,
      );
      _setToken(result.accessToken);
      return LoginResponse(token: result.accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid credentials');
      }
      if (e.response?.statusCode == 400) {
        throw Exception('User not found');
      }
      throw Exception('Login failed');
    }
  }

  @override
  Future<RegisterResponse> register(String email, String password) async {
    try {
      final AcquireTokenResult result = await _api.register(
        email: email,
        password: password,
      );
      _setToken(result.accessToken);
      return RegisterResponse(id: result.user.id, token: result.accessToken);
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        throw Exception('User already exists');
      }
      rethrow;
    }
  }
}

@Riverpod(keepAlive: true)
AuthenticationRepository authenticationRepository(Ref ref) {
  return HttpAuthRepository(
    ref.read(acquireApiClientProvider),
    (String token) =>
        ref.read(networkRepositoryProvider.notifier).setToken(token),
  );
}
