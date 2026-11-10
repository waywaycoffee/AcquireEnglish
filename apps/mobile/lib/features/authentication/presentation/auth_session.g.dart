// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AuthSession)
final authSessionProvider = AuthSessionProvider._();

final class AuthSessionProvider
    extends $NotifierProvider<AuthSession, AuthSessionState> {
  AuthSessionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authSessionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authSessionHash();

  @$internal
  @override
  AuthSession create() => AuthSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthSessionState>(value),
    );
  }
}

String _$authSessionHash() => r'b07981daf7fd922f7609ea26decab99a1c1091e7';

abstract class _$AuthSession extends $Notifier<AuthSessionState> {
  AuthSessionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AuthSessionState, AuthSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthSessionState, AuthSessionState>,
              AuthSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
