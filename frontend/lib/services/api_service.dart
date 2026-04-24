import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/analysis_models.dart';

const String kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8000',
);

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;

  const ApiService({this.baseUrl = kBackendUrl});

  // ── Auth headers ─────────────────────────────────────────────────────────
  Future<Map<String, String>> _authHeaders() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};
      final token = await user.getIdToken();
      return {'Authorization': 'Bearer $token'};
    } catch (_) {
      return {};
    }
  }

  // ── Upload + analyze in one shot (demo-friendly) ──────────────────────────
  Future<AnalysisResult> uploadAndAnalyze({
    required Uint8List fileBytes,
    required String filename,
    required String userId,
    required String targetColumn,
    required List<String> protectedAttributes,
    required String positiveLabel,
    bool intersectional = false,
  }) async {
    final uri = Uri.parse('$baseUrl/analyze/upload-and-analyze');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..fields['target_column'] = targetColumn
      ..fields['protected_attributes'] = protectedAttributes.join(',')
      ..fields['positive_label'] = positiveLabel
      ..fields['intersectional'] = intersectional.toString()
      ..files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
      );

    request.headers.addAll(await _authHeaders());

    final streamed = await request.send().timeout(const Duration(seconds: 180));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      final detail = _extractDetail(body);
      throw ApiException(streamed.statusCode, detail);
    }
    return AnalysisResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  // ── Preview CSV columns before full analysis ──────────────────────────────
  Future<PreviewResponse> previewDataset({
    required Uint8List fileBytes,
    required String filename,
  }) async {
    final uri = Uri.parse('$baseUrl/analyze/preview');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
      );

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, _extractDetail(body));
    }
    return PreviewResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  // ── Upload file to Firebase Storage ──────────────────────────────────────
  Future<String> uploadFile(
      Uint8List fileBytes, String filename, String userId) async {
    final uri = Uri.parse('$baseUrl/analyze/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
      );
    request.headers.addAll(await _authHeaders());

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, _extractDetail(body));
    }
    return (jsonDecode(body) as Map<String, dynamic>)['download_url'] as String;
  }

  // ── Run analysis from Firebase Storage URL ────────────────────────────────
  Future<AnalysisResult> runAnalysis(AnalysisRequest request) async {
    final uri = Uri.parse('$baseUrl/analyze');
    final headers = {'Content-Type': 'application/json', ...await _authHeaders()};
    final response = await http
        .post(uri, headers: headers, body: jsonEncode(request.toJson()))
        .timeout(const Duration(seconds: 180));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _extractDetail(response.body));
    }
    return AnalysisResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── Batch analysis ────────────────────────────────────────────────────────
  Future<List<BatchSummary>> batchAnalyze({
    required Uint8List zipBytes,
    required String filename,
    required String userId,
    required String targetColumn,
    required List<String> protectedAttributes,
    required String positiveLabel,
    bool intersectional = false,
  }) async {
    final uri = Uri.parse('$baseUrl/analyze/batch');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_id'] = userId
      ..fields['target_column'] = targetColumn
      ..fields['protected_attributes'] = protectedAttributes.join(',')
      ..fields['positive_label'] = positiveLabel
      ..fields['intersectional'] = intersectional.toString()
      ..files.add(
        http.MultipartFile.fromBytes('file', zipBytes, filename: filename),
      );
    request.headers.addAll(await _authHeaders());

    final streamed =
        await request.send().timeout(const Duration(seconds: 300));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, _extractDetail(body));
    }
    final list = jsonDecode(body) as List;
    return list
        .map((e) => BatchSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Trend data ────────────────────────────────────────────────────────────
  Future<List<TrendPoint>> getTrend(String userId, {int weeks = 12}) async {
    final uri = Uri.parse('$baseUrl/analyze/trend/$userId?weeks=$weeks');
    final headers = await _authHeaders();
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _extractDetail(response.body));
    }
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Audit history ─────────────────────────────────────────────────────────
  Future<List<AnalysisSummary>> getHistory(String userId) async {
    final uri = Uri.parse('$baseUrl/analyze/history/$userId');
    final headers = await _authHeaders();
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _extractDetail(response.body));
    }
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => AnalysisSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Get full report ───────────────────────────────────────────────────────
  Future<AnalysisResult> getReport(String auditId) async {
    final uri = Uri.parse('$baseUrl/reports/$auditId');
    final headers = await _authHeaders();
    final response =
        await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _extractDetail(response.body));
    }
    return AnalysisResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ── Delete report ─────────────────────────────────────────────────────────
  Future<void> deleteReport(String auditId) async {
    final uri = Uri.parse('$baseUrl/reports/$auditId');
    final headers = await _authHeaders();
    final response =
        await http.delete(uri, headers: headers).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _extractDetail(response.body));
    }
  }

  // ── Health check ──────────────────────────────────────────────────────────
  Future<bool> isHealthy() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _extractDetail(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['detail']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
