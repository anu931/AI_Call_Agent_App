// lib/services/api_service.dart

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';  // ✅ ADD THIS

class ApiService {
  static String get _base => AppConfig.baseUrl;  
  // ── Call Log ──────────────────────────────────────────────────────────────

  static Future<void> saveCall({
    required String number,
    required int duration,
    required String recording,
    required String date,
    required String time,
    String name = 'Unknown',
  }) async {
    try {
      await http.post(
        Uri.parse('$_base/calls/log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'number': number,
          'name': name,
          'duration': duration,
          'recording': recording,
          'date': date,
          'time': time,
        }),
      );
    } catch (_) {}
  }

  static Future<List<Map>> fetchCalls() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/calls/log'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (res.statusCode == 200) {
        return List<Map>.from(jsonDecode(res.body)['calls']);
      }
    } catch (_) {}
    return [];
  }

  // ── Upload Recording ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadRecording({
    required String filePath,
    required String number,
    required String name,
  }) async {
    try {
      // Step 1: Upload file → get task_id + call_log_id
      final uri = Uri.parse('$_base/calls/upload-recording'); // ✅ fixed path
      final request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.fields['phone_number'] = number;
      request.fields['contact_name'] = name;

      final file = File(filePath);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      request.files.add(http.MultipartFile(
        'audio_file',
        stream,
        length,
        filename: filePath.split('/').last,
      ));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        return {'error': 'Upload failed: ${response.statusCode}\n$body'};
      }

      final uploadResult = jsonDecode(body) as Map<String, dynamic>;
      final taskId = uploadResult['task_id'] as String?;
      final callLogId = uploadResult['call_log_id'];

      if (taskId == null || callLogId == null) {
        return {'error': 'Server did not return task_id or call_log_id'};
      }

      // Step 2: Poll Celery task status until complete (max 5 minutes)
      for (int i = 0; i < 120; i++) { 
  await Future.delayed(const Duration(seconds: 5));


        final statusRes = await http.get(
          Uri.parse('$_base/calls/task/$taskId'),
          headers: {'ngrok-skip-browser-warning': 'true'},
        );

        if (statusRes.statusCode == 200) {
          final statusData = jsonDecode(statusRes.body);
          final status = statusData['status'] as String? ?? '';

          if (status == 'SUCCESS') {
            // Step 3: Fetch the actual analysis result
            final analysisRes = await http.get(
              Uri.parse('$_base/calls/analysis/$callLogId'),
              headers: {'ngrok-skip-browser-warning': 'true'},
            );
            if (analysisRes.statusCode == 200) {
              return jsonDecode(analysisRes.body) as Map<String, dynamic>;
            }
            return {'error': 'Analysis fetch failed: ${analysisRes.statusCode}'};
          }

          if (status == 'FAILURE') {
            return {'error': 'AI processing failed. Please try again.'};
          }
          // else PENDING or STARTED → keep polling
        }
      }

      return {'error': 'Processing timed out after 3 minutes. Try checking results later.'};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ── Stats & Issues ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> fetchStats() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/calls/stats'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return {};
  }

  static Future<List<Map>> fetchIssues() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/calls/issues'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (res.statusCode == 200) {
        return List<Map>.from(jsonDecode(res.body)['issues']);
      }
    } catch (_) {}
    return [];
  }
}