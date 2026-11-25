import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Advanced API-key / debug rows stay hidden unless unlocked (7 taps on version).
class DeveloperModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;
}

final NotifierProvider<DeveloperModeNotifier, bool> developerModeProvider =
    NotifierProvider<DeveloperModeNotifier, bool>(DeveloperModeNotifier.new);

class VersionTapCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;

  void reset() => state = 0;
}

final NotifierProvider<VersionTapCountNotifier, int> versionTapCountProvider =
    NotifierProvider<VersionTapCountNotifier, int>(VersionTapCountNotifier.new);
