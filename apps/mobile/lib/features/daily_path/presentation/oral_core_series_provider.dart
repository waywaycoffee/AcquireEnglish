import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repository/network_repository.dart';
import '../domain/oral_core_series.dart';

final oralCoreSeriesProvider =
    FutureProvider<OralCoreSeries>((Ref ref) async {
  try {
    final Dio dio = ref.read(networkRepositoryProvider);
    final Response<dynamic> response = await dio.get(
      '/api/content/courses/${OralCoreSeries.kSeriesId}',
    );
    final Object? data = response.data;
    if (data is Map && data['lessons'] is List) {
      return OralCoreSeries.fromJson(Map<String, dynamic>.from(data));
    }
  } catch (_) {}

  final String raw = await rootBundle.loadString(OralCoreSeries.kAssetPath);
  return OralCoreSeries.fromJson(
    Map<String, dynamic>.from(jsonDecode(raw) as Map),
  );
});
