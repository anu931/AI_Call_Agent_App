// lib/screens/home_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;
  int _totalCalls = 0, _totalIssues = 0, _positive = 0, _neutral = 0, _negative = 0;
  List<Map<String, dynamic>> _topIssues = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http
          .get(
            Uri.parse('${AppConfig.backendBase}/calls/stats'),
            headers: AppConfig.ngrokHeaders,   // ✅ ngrok header added
          )
          .timeout(const Duration(seconds: 30));

      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _totalCalls  = d['total_calls']  as int? ?? 0;
          _totalIssues = d['total_issues'] as int? ?? 0;
          _positive    = d['positive']     as int? ?? 0;
          _neutral     = d['neutral']      as int? ?? 0;
          _negative    = d['negative']     as int? ?? 0;
          _topIssues   = (d['top_issues'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server error ${r.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(children: [
                        _StatBox(label: 'Total Calls',   value: '$_totalCalls',  color: Colors.blueAccent),
                        const SizedBox(width: 12),
                        _StatBox(label: 'Unique Issues', value: '$_totalIssues', color: Colors.orangeAccent),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        _StatBox(label: '😊 Positive', value: '$_positive', color: Colors.green),
                        const SizedBox(width: 8),
                        _StatBox(label: '😐 Neutral',  value: '$_neutral',  color: Colors.grey),
                        const SizedBox(width: 8),
                        _StatBox(label: '😠 Negative', value: '$_negative', color: Colors.red),
                      ]),
                      const SizedBox(height: 24),
                      const Text('Top Issues by Frequency',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      if (_topIssues.isEmpty)
                        const Text('No issues recorded yet.',
                            style: TextStyle(color: Colors.grey))
                      else
                        ..._topIssues.map((i) => _IssueRow(issue: i)),
                    ],
                  ),
                ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    ),
  );
}

class _IssueRow extends StatelessWidget {
  final Map<String, dynamic> issue;
  const _IssueRow({required this.issue});

  @override
  Widget build(BuildContext context) {
    final count = issue['count'] as int? ?? 1;
    final title = issue['title'] as String? ?? '';
    final color = count >= 6
        ? Colors.red.shade900
        : count >= 3
            ? Colors.brown.shade800
            : Colors.blueGrey.shade800;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
          child: Text('×$count',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.white)),
        ),
      ]),
    );
  }
}