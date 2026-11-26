import 'package:common_learn_english/features/tv/presentation/tv_remote_voice_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TV mic keys include microphoneToggle and optional space', () {
    expect(
      isTvPrimaryMicKey(LogicalKeyboardKey.microphoneToggle, allowSpace: false),
      isTrue,
    );
    expect(
      isTvPrimaryMicKey(LogicalKeyboardKey.mediaRecord, allowSpace: false),
      isTrue,
    );
    expect(
      isTvPrimaryMicKey(LogicalKeyboardKey.space, allowSpace: false),
      isFalse,
    );
    expect(
      isTvPrimaryMicKey(LogicalKeyboardKey.space, allowSpace: true),
      isTrue,
    );
    expect(
      isTvPrimaryMicKey(LogicalKeyboardKey.enter, allowSpace: true),
      isFalse,
    );
  });
}
