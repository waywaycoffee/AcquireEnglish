import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repository/network_repository.dart';

part 'auth_session.g.dart';

class AuthSessionState {
  const AuthSessionState({
    this.accessToken = '',
    this.email = '',
    this.displayName = '',
    this.memberNo = '',
  });

  final String accessToken;
  final String email;
  final String displayName;
  /// Public registration serial from API, e.g. AE-000123.
  final String memberNo;

  bool get isLoggedIn => accessToken.isNotEmpty;

  AuthSessionState copyWith({
    String? accessToken,
    String? email,
    String? displayName,
    String? memberNo,
  }) => AuthSessionState(
    accessToken: accessToken ?? this.accessToken,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    memberNo: memberNo ?? this.memberNo,
  );
}

@Riverpod(keepAlive: true)
class AuthSession extends _$AuthSession {
  static const String _tokenKey = 'authAccessToken';
  static const String _emailKey = 'authEmail';
  static const String _nameKey = 'authDisplayName';
  static const String _memberNoKey = 'authMemberNo';

  Box<String>? get _prefsOrNull {
    if (!Hive.isBoxOpen('prefs')) {
      return null;
    }
    return Hive.box<String>('prefs');
  }

  @override
  AuthSessionState build() {
    final Box<String>? prefs = _prefsOrNull;
    final String token = prefs?.get(_tokenKey) ?? '';
    final String email = prefs?.get(_emailKey) ?? '';
    final String displayName = prefs?.get(_nameKey) ?? '';
    final String memberNo = prefs?.get(_memberNoKey) ?? '';
    if (token.isNotEmpty) {
      ref.read(networkRepositoryProvider.notifier).setToken(token);
    }
    return AuthSessionState(
      accessToken: token,
      email: email,
      displayName: displayName,
      memberNo: memberNo,
    );
  }

  Future<void> signIn({
    required String accessToken,
    required String email,
    String? displayName,
    String? memberNo,
  }) async {
    final Box<String>? prefs = _prefsOrNull;
    await prefs?.put(_tokenKey, accessToken);
    await prefs?.put(_emailKey, email);
    await prefs?.put(_nameKey, displayName ?? '');
    if (memberNo != null) {
      await prefs?.put(_memberNoKey, memberNo);
    }
    ref.read(networkRepositoryProvider.notifier).setToken(accessToken);
    state = AuthSessionState(
      accessToken: accessToken,
      email: email,
      displayName: displayName ?? '',
      memberNo: memberNo ?? state.memberNo,
    );
  }

  Future<void> updateProfile({String? displayName, String? memberNo}) async {
    final Box<String>? prefs = _prefsOrNull;
    final String nextName = displayName ?? state.displayName;
    final String nextNo = memberNo ?? state.memberNo;
    await prefs?.put(_nameKey, nextName);
    await prefs?.put(_memberNoKey, nextNo);
    state = state.copyWith(displayName: nextName, memberNo: nextNo);
  }

  Future<void> signOut() async {
    final Box<String>? prefs = _prefsOrNull;
    await prefs?.delete(_tokenKey);
    await prefs?.delete(_emailKey);
    await prefs?.delete(_nameKey);
    await prefs?.delete(_memberNoKey);
    ref.read(networkRepositoryProvider.notifier).clearToken();
    state = const AuthSessionState();
  }
}
