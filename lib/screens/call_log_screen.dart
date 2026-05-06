import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'analysis_screen.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  static const _channel = MethodChannel('com.example.crm_app/call_logs');
  static const _base    = 'http://192.168.1.6:8000';

  List<Map<String, dynamic>> _logs      = [];
  Map<int, Map<String, dynamic>> _analysis = {}; // call id → analysis
  Set<int> _polling                     = {};    // ids currently being polled
  bool _loading                         = true;
  final AudioPlayer _player             = AudioPlayer();
  int? _playingId;
  bool _isPlaying                       = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        setState(() { _playingId = null; _isPlaying = false; });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // ── Load local call logs from Android DB ────────────────────────────────────
  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final raw = await _channel.invokeMethod('getCallLogs') as List<dynamic>;
      final logs = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() { _logs = logs; _loading = false; });

      // For each log, fetch existing analysis then start polling if not done
      for (final log in logs) {
        final id = log['id'] as int;
        await _fetchAnalysis(id);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ── Fetch analysis once ──────────────────────────────────────────────────────
  Future<void> _fetchAnalysis(int callId) async {
    try {
      final r = await http
          .get(Uri.parse('$_base/calls/analysis/$callId'))
          .timeout(const Duration(seconds: 8));

      if (r.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
        setState(() => _analysis[callId] = data);

        final status = data['status'] as String? ?? 'pending';
        if (status != 'done' && status != 'error') {
          _startPolling(callId);
        }
      } else if (r.statusCode == 404) {
        // Analysis not created yet — start polling
        _startPolling(callId);
      }
    } catch (_) {
      _startPolling(callId);
    }
  }

  // ── Poll until done ──────────────────────────────────────────────────────────
  void _startPolling(int callId) {
    if (_polling.contains(callId)) return;
    _polling.add(callId);

    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted) { timer.cancel(); return; }

      try {
        final r = await http
            .get(Uri.parse('$_base/calls/analysis/$callId'))
            .timeout(const Duration(seconds: 8));

        if (r.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
          setState(() => _analysis[callId] = data);

          final status = data['status'] as String? ?? 'pending';
          if (status == 'done' || status == 'error') {
            timer.cancel();
            _polling.remove(callId);
          }
        }
      } catch (_) {}
    });
  }

  // ── Audio playback ───────────────────────────────────────────────────────────
  Future<void> _togglePlay(Map<String, dynamic> log) async {
    final id   = log['id'] as int;
    final path = log['recording_path'] as String? ?? '';

    if (_playingId == id && _isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }
    if (path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording file not found')));
      return;
    }
    try {
      await _player.setFilePath(path);
      await _player.play();
      setState(() { _playingId = id; _isPlaying = true; });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot play: $e')));
    }
  }

  // ── Delete ───────────────────────────────────────────────────────────────────
  Future<void> _delete(Map<String, dynamic> log) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Log'),
        content: Text('Delete log for ${log['phone_number']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _channel.invokeMethod('deleteCallLog', {'id': log['id']});
      _loadLogs();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _fmtDate(int ms) {
    final dt  = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today ${DateFormat('hh:mm a').format(dt)}';
    }
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  String _fmtDur(int sec) {
    final m = sec ~/ 60, s = sec % 60;
    return m == 0 ? '${s}s' : '${m}m ${s}s';
  }

  Color _sentimentColor(String? s) => switch (s) {
    'positive' => Colors.green,
    'negative' => Colors.red,
    _          => Colors.orange,
  };

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Logs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'test') {
                await _channel.invokeMethod('insertTestLog');
                _loadLogs();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'test', child: Text('Insert Test Log')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call_outlined, size: 72, color: Colors.grey.shade600),
                      const SizedBox(height: 12),
                      const Text('No call logs yet', style: TextStyle(fontSize: 17)),
                      const Text('Calls will appear here automatically',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ))
              : RefreshIndicator(
                  onRefresh: _loadLogs,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => _buildCard(_logs[i]),
                  ),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> log) {
    final id           = log['id'] as int;
    final number       = log['phone_number'] as String? ?? 'Unknown';
    final callTime     = log['call_time']    as int? ?? 0;
    final duration     = log['duration']     as int? ?? 0;
    final isIncoming   = log['is_incoming']  as bool? ?? true;
    final recordPath   = log['recording_path'] as String? ?? '';
    final hasRecording = recordPath.isNotEmpty;
    final thisPlaying  = _playingId == id && _isPlaying;

    final analysis  = _analysis[id];
    final status    = analysis?['status'] as String?;
    final sentiment = analysis?['sentiment'] as String?;
    final issue     = analysis?['issue_title'] as String?;
    final isPolling = _polling.contains(id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: status == 'done'
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnalysisScreen(
                      callLogId: id,
                      phoneNumber: number,
                    ),
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: isIncoming
                    ? Colors.green.shade900
                    : Colors.blue.shade900,
                child: Icon(
                  isIncoming ? Icons.call_received : Icons.call_made,
                  color: isIncoming ? Colors.greenAccent : Colors.lightBlueAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),

              // Main info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Number + time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(number,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text('${_fmtDate(callTime)}  •  ${_fmtDur(duration)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Status / issue line
                    if (status == 'done' && issue != null)
                      Text(issue,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade300),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)
                    else if (isPolling || status == 'processing')
                      Row(children: [
                        SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.grey.shade500),
                        ),
                        const SizedBox(width: 6),
                        Text('Analysing...',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ])
                    else if (status == 'error')
                      Text('Analysis failed',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade400))
                    else
                      Text('Waiting for analysis',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),

                    const SizedBox(height: 6),

                    // Bottom row: sentiment + recording icon
                    Row(
                      children: [
                        if (status == 'done' && sentiment != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _sentimentColor(sentiment).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              sentiment,
                              style: TextStyle(
                                fontSize: 11,
                                color: _sentimentColor(sentiment),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (hasRecording) ...[
                          Icon(Icons.mic, size: 12, color: Colors.redAccent.shade100),
                          const SizedBox(width: 3),
                          Text('Recorded',
                              style: TextStyle(fontSize: 11, color: Colors.redAccent.shade100)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _togglePlay(log),
                            child: Icon(
                              thisPlaying ? Icons.pause_circle : Icons.play_circle,
                              color: Colors.lightBlueAccent,
                              size: 24,
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _delete(log),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}