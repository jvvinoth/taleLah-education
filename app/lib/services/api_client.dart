/// TaleLah API client — talks to the FastAPI backend.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/story_package.dart';

class ApiException implements Exception {
  final int statusCode;
  final String detail;
  ApiException(this.statusCode, this.detail);

  @override
  String toString() => detail;
}

class ApiClient {
  final String baseUrl;
  final http.Client _client = http.Client();
  String? _token;
  String? _adultId;

  ApiClient({required this.baseUrl});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // ── Auth ──────────────────────────────────────────────────────────────

  Future<String> register({
    required String email,
    required String displayName,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({'email': email, 'display_name': displayName}),
    );
    final data = jsonDecode(res.body);
    _token = data['access_token'];
    _adultId = data['adult_id'];
    return _adultId!;
  }

  Future<String?> login({required String email}) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _token = data['access_token'];
      _adultId = data['adult_id'];
      return _adultId;
    }
    return null;
  }

  String? get adultId => _adultId;

  // ── Child Profiles ────────────────────────────────────────────────────

  Future<ChildProfile> createProfile({
    required String alias,
    required String ageBand,
    String targetLocale = 'ta-SG',
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/profiles?adult_id=${_adultId ?? "demo"}'),
      headers: _headers,
      body: jsonEncode({
        'alias': alias,
        'age_band': ageBand,
        'target_locale': targetLocale,
      }),
    );
    return ChildProfile.fromJson(jsonDecode(res.body));
  }

  Future<List<ChildProfile>> getProfiles() async {
    final res = await _client.get(
      Uri.parse('$baseUrl/profiles?adult_id=${_adultId ?? "demo"}'),
      headers: _headers,
    );
    final list = jsonDecode(res.body) as List;
    return list.map((e) => ChildProfile.fromJson(e)).toList();
  }

  // ── Moments ───────────────────────────────────────────────────────────

  Future<Moment> captureMoment({
    required String childProfileId,
    required String text,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/moments'),
      headers: _headers,
      body: jsonEncode({
        'child_profile_id': childProfileId,
        'text': text,
      }),
    );
    return Moment.fromJson(jsonDecode(res.body));
  }

  // ── Story Generation ──────────────────────────────────────────────────

  Future<StoryPackageSummary> generatePackage({
    required String momentId,
    String locale = 'ta-SG',
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/packages/generate?moment_id=$momentId&locale=$locale'),
      headers: _headers,
    );
    return StoryPackageSummary.fromJson(jsonDecode(res.body));
  }

  /// Start async generation — returns packageId. Use SSE stream for progress.
  Future<String> generatePackageAsync({
    required String momentId,
    String locale = 'ta-SG',
  }) async {
    final res = await _client.post(
      Uri.parse(
          '$baseUrl/packages/generate-async?moment_id=$momentId&locale=$locale'),
      headers: _headers,
    );
    final data = jsonDecode(res.body);
    return data['package_id'] as String;
  }

  Future<Map<String, dynamic>> getPackageDetail(String packageId) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/packages/$packageId'),
      headers: _headers,
    );
    return jsonDecode(res.body);
  }

  Future<void> approvePackage(String packageId) async {
    await _client.post(
      Uri.parse('$baseUrl/packages/$packageId/approve'),
      headers: _headers,
      body: jsonEncode({'approved': true}),
    );
  }

  /// F3 — answer the one clarification question; pipeline resumes via SSE.
  Future<void> clarifyPackage(String packageId, String answer) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/packages/$packageId/clarify'),
      headers: _headers,
      body: jsonEncode({'answer': answer}),
    );
    if (res.statusCode >= 400) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(
          res.statusCode, data['detail']?.toString() ?? res.body);
    }
  }

  // ── Parent Review & Edit (F2) ────────────────────────────────────

  Map<String, dynamic> _jsonOrThrow(http.Response res) {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
          res.statusCode, data['detail']?.toString() ?? res.body);
    }
    return data;
  }

  Future<Map<String, dynamic>> editFacts(
      String packageId, List<String> facts) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/packages/$packageId/facts'),
      headers: _headers,
      body: jsonEncode({'facts': facts}),
    );
    return _jsonOrThrow(res);
  }

  Future<Map<String, dynamic>> swapTargetWord(
      String packageId, String oldWord, String newWord) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/packages/$packageId/target-word'),
      headers: _headers,
      body: jsonEncode({'old_word': oldWord, 'new_word': newWord}),
    );
    return _jsonOrThrow(res);
  }

  Future<Map<String, dynamic>> setDifficulty(
      String packageId, String level) async {
    final res = await _client.patch(
      Uri.parse('$baseUrl/packages/$packageId/difficulty'),
      headers: _headers,
      body: jsonEncode({'level': level}),
    );
    return _jsonOrThrow(res);
  }

  Future<Map<String, dynamic>> regenerateComponent(
    String packageId,
    String component, {
    int sceneIndex = 0,
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/packages/$packageId/regenerate'),
      headers: _headers,
      body: jsonEncode({'component': component, 'scene_index': sceneIndex}),
    );
    return _jsonOrThrow(res);
  }

  Future<List<Map<String, dynamic>>> getWordBank(String locale) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/packs/$locale/word-bank'),
      headers: _headers,
    );
    final data = _jsonOrThrow(res);
    return (data['word_bank'] as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }

  // ── SSE Stream ────────────────────────────────────────────────────────

  /// Subscribe to SSE events for a package. Returns a stream of SSEEvent.
  Stream<SSEEvent> streamPackageEvents(String packageId) {
    final uri = Uri.parse('$baseUrl/packages/$packageId/stream');
    final request = http.Request('GET', uri);
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }

    final controller = StreamController<SSEEvent>();

    _client.send(request).then((response) {
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6);
            try {
              final event = SSEEvent.fromJson(jsonDecode(jsonStr));
              controller.add(event);
              if (event.type == 'generation_complete' ||
                  event.type == 'error') {
                controller.close();
              }
            } catch (_) {
              // skip non-JSON lines
            }
          }
        },
        onDone: () {
          if (!controller.isClosed) controller.close();
        },
        onError: (e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    });

    return controller.stream;
  }

  // ── Health ────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      final res = await _client.get(Uri.parse('$baseUrl/health'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
