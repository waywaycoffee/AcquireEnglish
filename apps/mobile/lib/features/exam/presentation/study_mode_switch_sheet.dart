import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Formerly switched acquisition ↔ exam. Product is unified under acquisition;
/// this now only opens exam-target selection for any leftover call sites.
Future<void> showStudyModeSwitchSheet(BuildContext context, WidgetRef ref) {
  return context.push<void>('/exam/select');
}
