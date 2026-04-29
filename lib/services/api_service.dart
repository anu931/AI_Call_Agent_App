import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const _base = 'http://192.168.1.6:8000';

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
          'number': number, 'name': name, 'duration': duration,
          'recording': recording, 'date': date, 'time': time,
        }),
      );
    } catch (e) {
      // Silent fail
    }
  }

  static Future<List<Map>> fetchCalls() async {
    try {
      final res = await http.get(Uri.parse('$_base/calls/log'));
      if (res.statusCode == 200) {
        return List<Map>.from(jsonDecode(res.body)['calls']);
      }
    } catch (_) {}
    return [];
  }
}