import 'package:common_learn_english/features/learning_modules/assessment_panel.dart';
import 'package:common_learn_english/features/authentication/presentation/auth_session.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class AssessmentAuth extends AuthSession {
  @override
  AuthSessionState build() => const AuthSessionState(
    accessToken: 'signed-in',
    email: 'tester@example.test',
  );
}

class UnconfiguredApi extends AcquireApiClient {
  UnconfiguredApi() : super(Dio());
  int statuses = 0;
  @override
  Future<Map<String, dynamic>> assessmentStatus() async {
    statuses++;
    return {'configured': false};
  }
}

void main() {
  testWidgets(
    'no microphone request before click and unconfigured service does not record',
    (tester) async {
      final api = UnconfiguredApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(AssessmentAuth.new),
            acquireApiClientProvider.overrideWithValue(api),
          ],
          child: const MaterialApp(
            home: Scaffold(body: AssessmentPanel(reference: 'hello')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.statuses, 0);
      await tester.tap(find.text('开始录音'));
      await tester.pumpAndSettle();
      expect(api.statuses, 1);
      expect(find.text('腾讯云评测尚未配置，请联系管理员'), findsOneWidget);
      expect(find.text('结束录音并评测'), findsNothing);
    },
  );
}
