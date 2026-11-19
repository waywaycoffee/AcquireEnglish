/// Primary owner / default test account for this product build.
///
/// Used to auto-sign-in when the device has no saved session, so personal
/// subtitle assets and watch URLs sync against the same cloud user.
class DefaultAccount {
  const DefaultAccount._();

  static const String email = String.fromEnvironment('DEMO_ACCOUNT_EMAIL');
  static const String password = String.fromEnvironment('DEMO_ACCOUNT_PASSWORD');
  static const String displayName = 'weiwei';
}
