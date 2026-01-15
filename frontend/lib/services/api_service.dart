import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/kiosk_status.dart';

class ApiService {
  // When served by Flask (same origin), empty string works best.
  // It effectively makes requests to "/api/status" on the current domain.
  static const String baseUrl = '';

  // Helper to construct Uri
  Uri _getUri(String path, [Map<String, dynamic>? queryParams]) {
    // For relative paths in Flutter Web, we just pass the path.
    // However, Uri.parse requires a scheme/host for full URLs or we handle it carefully.
    // standard http package might need a full URL if not browser client?
    // Actually, simply passing the path works in browser-based http clients.

    // Better robustness: If baseUrl is empty, use Uri(path: path, queryParameters: queryParams)
    if (baseUrl.isEmpty) {
      return Uri(path: path, queryParameters: queryParams);
    }

    String url = '$baseUrl$path';
    return Uri.parse(url).replace(queryParameters: queryParams);
  }

  Future<KioskStatus> getStatus(String token) async {
    final uri = _getUri('/api/status', {'token': token});

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return KioskStatus.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> scanCode(String token, String code) async {
    final uri = _getUri('/api/scan');

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'token': token, 'code': code}),
      );

      final body = json.decode(response.body);

      if (response.statusCode == 200 ||
          response.statusCode == 400 ||
          response.statusCode == 403 ||
          response.statusCode == 404 ||
          response.statusCode == 409) {
        // Return the body even for expected "errors" like "Banned" or "Denied"
        // The UI will handle the 'ok' flag.
        return body;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // --- ADMIN API ---
  Future<Map<String, dynamic>> getAdminStats() async {
    final uri = _getUri('/api/admin/stats');
    final response = await http.get(uri);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load admin stats: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getAdminRoster() async {
    final uri = _getUri('/api/admin/roster');
    final response = await http.get(uri);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load roster: ${response.statusCode}');
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    final uri = _getUri('/api/settings/update');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(settings),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) {
      throw Exception('Failed to update settings');
    }
  }

  Future<void> updateSlug(String slug) async {
    final uri = _getUri('/api/settings/slug');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'slug': slug}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 409) throw Exception('Slug taken');
    if (response.statusCode != 200) throw Exception('Failed to update slug');
  }

  Future<void> suspendKiosk(bool suspend) async {
    final uri = _getUri('/api/settings/suspend');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'suspend': suspend}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to suspend');
  }

  Future<int> uploadRoster(List<int> bytes, String filename) async {
    final uri = _getUri('/api/roster/upload');
    var request = http.MultipartRequest('POST', uri);
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return body['count'] ?? 0;
    }
    throw Exception('Failed to upload roster: ${response.body}');
  }

  Future<List<Map<String, dynamic>>> getPassLogs() async {
    final uri = _getUri('/api/admin/logs');
    final response = await http.get(uri);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return List<Map<String, dynamic>>.from(body['logs']);
    }
    throw Exception('Failed to load logs: ${response.statusCode}');
  }

  Future<List<Map<String, dynamic>>> fetchRoster() async {
    final uri = _getUri('/api/roster');
    final response = await http.get(uri);
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return List<Map<String, dynamic>>.from(body['roster']);
    }
    throw Exception('Failed to fetch roster');
  }

  Future<void> addStudent(String name, String studentId) async {
    final uri = _getUri('/api/roster/add');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'student_id': studentId}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 409)
      throw Exception('Student ID already exists');
    if (response.statusCode != 200) throw Exception('Failed to add student');
  }

  Future<void> deleteStudent(int id) async {
    final uri = _getUri('/api/roster/$id');
    final response = await http.delete(uri);
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to delete student');
  }

  Future<void> joinQueue(String code, String token) async {
    final uri = _getUri('/api/queue/join');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'code': code, 'token': token}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to join queue');
    }
  }

  Future<void> leaveQueue(String code, String token) async {
    final uri = _getUri('/api/queue/leave');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'code': code}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to leave queue');
    }
  }

  Future<void> deleteFromQueue(String studentId, String token) async {
    final uri = _getUri('/api/queue/delete');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'student_id': studentId}),
    );
    // Note: Admin authentication is cookie-based, so token might not be needed?
    // Actually, /api/queue/delete uses @require_admin_auth_api which checks session cookie.
    // But let's check if we need to pass anything. The wrapper checks session.
    // However, our ApiService helper usually relies on cookie preservation.
    // Flutter Web preserves cookies automatically in browser.

    if (response.statusCode != 200) {
      throw Exception('Failed to delete from queue');
    }
  }

  Future<void> reorderQueue(List<String> studentIds) async {
    final uri = _getUri('/api/queue/reorder');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'student_ids': studentIds}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to reorder queue');
  }

  Future<void> toggleBan(String nameHash, bool banned) async {
    final uri = _getUri('/api/roster/ban');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name_hash': nameHash, 'banned': banned}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to toggle ban');
  }

  Future<void> clearRoster({bool clearHistory = false}) async {
    final uri = _getUri('/api/admin/reset');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'clear_roster': true, 'clear_sessions': clearHistory}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to clear roster');
  }

  Future<int> banOverdue() async {
    final uri = _getUri('/api/control/ban_overdue');
    final response = await http.post(uri);
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return body['count'] ?? 0;
    }
    throw Exception('Failed to ban overdue');
  }

  Future<void> deleteHistory() async {
    final uri = _getUri('/api/admin/reset');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'clear_sessions': true, 'clear_roster': false}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to delete history');
  }

  Future<void> endSession(int sessionId) async {
    final uri = _getUri('/api/admin/end_session');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'session_id': sessionId}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to end session');
  }

  Future<void> banStudent(String studentId) async {
    final uri = _getUri('/api/ban_student');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'student_id': studentId}),
    );
    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode != 200) throw Exception('Failed to ban student');
  }

  // --- DEV API ---
  Future<bool> devAuth(String passcode) async {
    final uri = _getUri('/api/dev/auth');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'passcode': passcode}),
    );

    if (response.statusCode == 200) {
      final body = json.decode(response.body);
      return body['ok'] == true;
    }
    return false;
  }

  Future<Map<String, dynamic>> getDevStats() async {
    final uri = _getUri('/api/dev/stats');
    final response = await http.get(uri);

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load dev stats: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> getExpandedDevStats() async {
    final uri = _getUri('/api/dev/expanded_stats');
    // POST request with empty body (cookie-based auth)
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({}),
    );

    if (response.statusCode == 401) throw Exception('Unauthorized');
    if (response.statusCode == 200) return json.decode(response.body);
    throw Exception('Failed to load expanded stats: ${response.statusCode}');
  }
}
