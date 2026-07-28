/// TaleLah API client — talks to the FastAPI backend.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  /// F5 — voice note ≤45 s; backend transcribes via the pack's ASR provider.
  Future<Moment> captureMomentVoice({
    required String childProfileId,
    required List<int> audioBytes,
    String locale = 'ta-SG',
  }) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/moments/voice'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields['child_profile_id'] = childProfileId;
    req.fields['locale'] = locale;
    req.files.add(
        http.MultipartFile.fromBytes('audio', audioBytes, filename: 'note.wav'));
    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _detail(res, 'Voice capture failed'));
    }
    return Moment.fromJson(jsonDecode(res.body));
  }

  /// F5 — photo ≤10 MB; Qwen-VL-Max turns it into moment facts.
  Future<Moment> captureMomentPhoto({
    required String childProfileId,
    required List<int> imageBytes,
    String contentType = 'image/jpeg',
  }) async {
    final req = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/moments/photo'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields['child_profile_id'] = childProfileId;
    final ext = contentType.split('/').last;
    req.files.add(http.MultipartFile.fromBytes(
      'image',
      imageBytes,
      filename: 'moment.$ext',
      contentType: MediaType.parse(contentType),
    ));
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, _detail(res, 'Photo capture failed'));
    }
    return Moment.fromJson(jsonDecode(res.body));
  }

  String _detail(http.Response res, String fallback) {
    try {
      return jsonDecode(res.body)['detail'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
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

  /// Story library — all packages, newest first.
  Future<List<StoryPackageSummary>> listPackages(
      {String childProfileId = ''}) async {
    final query = childProfileId.isEmpty
        ? ''
        : '?child_profile_id=$childProfileId';
    final res = await _client.get(
      Uri.parse('$baseUrl/packages$query'),
      headers: _headers,
    );
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => StoryPackageSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── F6 · Child session + bounded speech turn ──────────────────────

  /// Start a child session for an approved package → session_id.
  Future<String?> startSession(String packageId) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/sessions/start'),
      headers: _headers,
      body: jsonEncode({'story_package_id': packageId}),
    );
    if (res.statusCode >= 400) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['session_id'] as String?;
  }

  /// Upload a child speech clip — backend transcribes + fuzzy-matches
  /// against the pack's expected intents only. Raw audio is discarded
  /// server-side; the transcript never comes back.
  Future<Map<String, dynamic>> speechTurn({
    required String sessionId,
    required List<int> audioBytes,
    String expectedIntent = '',
    int attempt = 1,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/sessions/$sessionId/speech-turn'),
    );
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields['expected_intent'] = expectedIntent;
    req.fields['attempt'] = '$attempt';
    req.files.add(http.MultipartFile.fromBytes(
      'audio',
      audioBytes,
      filename: 'clip.wav',
    ));
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Speech turn failed');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Picture-choice fallback tap — always celebrates (AC-04).
  Future<Map<String, dynamic>> speechFallback(
      String sessionId, String selectedWord) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/sessions/$sessionId/speech-fallback'),
      headers: _headers,
      body: jsonEncode({'selected_word': selectedWord}),
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Fallback failed');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Sprint 4 · F8/F9/F10 — session milestones, summary, memories ──

  /// F8/F9 — report a mission/handoff milestone. Fire-and-forget safe.
  Future<void> sessionEvent(String sessionId, String kind) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/sessions/$sessionId/event'),
    );
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.fields['kind'] = kind;
    await req.send().timeout(const Duration(seconds: 15));
  }

  /// Session summary — celebration, no grades (F10).
  Future<Map<String, dynamic>> completeSession(String sessionId) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/sessions/$sessionId/complete'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Complete failed');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// F10 — save a memory; backend refuses without the consent tick.
  Future<Map<String, dynamic>> saveMemory({
    required String sessionId,
    required bool consent,
    String note = '',
  }) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/memories'),
      headers: _headers,
      body: jsonEncode(
          {'session_id': sessionId, 'consent': consent, 'note': note}),
    );
    return _jsonOrThrow(res);
  }

  Future<List<Map<String, dynamic>>> listMemories(
      {String childProfileId = ''}) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/memories?child_profile_id=$childProfileId'),
      headers: _headers,
    );
    final data = _jsonOrThrow(res);
    return (data['memories'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// Deletes the memory row AND the package media (F10).
  Future<void> deleteMemory(String memoryId) async {
    final res = await _client.delete(
      Uri.parse('$baseUrl/memories/$memoryId'),
      headers: _headers,
    );
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'Delete failed');
    }
  }

  /// North-star metric only — family moments this week (hard rule 6).
  Future<int> getProgress(String childProfileId) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/progress/$childProfileId'),
      headers: _headers,
    );
    final data = _jsonOrThrow(res);
    return data['family_moments_this_week'] as int? ?? 0;
  }

  /// F9 — parent-facing handoff copy straight from the language pack.
  Future<Map<String, dynamic>> getFamilyCopy(String locale) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/packs/$locale/family-copy'),
      headers: _headers,
    );
    final data = _jsonOrThrow(res);
    return (data['family_copy'] as Map? ?? {}).cast<String, dynamic>();
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
