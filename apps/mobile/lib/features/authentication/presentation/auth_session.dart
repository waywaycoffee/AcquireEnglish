import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repository/network_repository.dart';

part 'auth_session.g.dart';

class AuthSessionState {
  const AuthSessionState({
    this.accessToken = '',
    this.email = '',
    this.displayName = '',
  });

  final String accessToken;
  final String email;
  final String displayName;

  bool get isLoggedIn => accessToken.isNotEmpty;

  AuthSessionState copyWith({
    String? accessToken,
    String? email,
    String? displayName,
  }) => AuthSessionState(
    accessToken: accessToken ?? this.accessToken,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
  );
}

@Riverpod(keepAlive: true)
class AuthSession extends _$AuthSession {
  static const String _tokenKey = 'authAccessToken';
  static const String _emailKey = 'authEmail';
  static const String _nameKey = 'authDisplayName';

  Box<String> get _prefs => Hive.box<String>('prefs');

  @override
  AuthSessionState build() {
    final String token = _prefs.get(_tokenKey) ?? '';
    final String email = _prefs.get(_emailKey) ?? '';
    final String displayName = _prefs.get(_nameKey) ?? '';
    if (token.isNotEmpty) {
      ref.read(networkRepositoryProvider.notifier).setToken(token);
    }
    return AuthSessionState(
      accessToken: token,
      email: email,
      displayName: displayName,
    );
  }

  Future<void> signIn({
    required String accessToken,
    required String email,
    String? displayName,
  }) async {
    await _prefs.put(_tokenKey, accessToken);
    await _prefs.put(_emailKey, email);
    await _prefs.put(_nameKey, displayName ?? '');
    ref.read(networkRepositoryProvider.notifier).setToken(accessToken);
    state = AuthSessionState(
      accessToken: accessToken,
      email: email,
      displayName: displayName ?? '',
    );
  }

  Future<void> signOut() async {
    await _prefs.delete(_tokenKey);
    await _prefs.delete(_emailKey);
    await _prefs.delete(_nameKey);
    ref.read(networkRepositoryProvider.notifier).clearToken();
    state = const AuthSessionState();
  }
}
