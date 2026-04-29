import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'analysis_screen.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  static const _channel = MethodChannel('com.example.crm_app/call_logs');

  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  final AudioPlayer _player = AudioPlayer();
  int? _playingId;
  bool _isPlaying = false;

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

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final raw = await _channel.invokeMethod('getCallLogs') as List<dynamic>;
      setState(() {
        _logs = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Logs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'test') { await _channel.invokeMethod('insertTestLog'); _loadLogs(); }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'test', child: Text('Insert Test Log'))],
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnalysisScreen(
              callLogId: id,
              phoneNumber: number,
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: isIncoming ? Colors.green.shade900 : Colors.blue.shade900,
          child: Icon(
            isIncoming ? Icons.call_received : Icons.call_made,
            color: isIncoming ? Colors.greenAccent : Colors.lightBlueAccent,
            size: 20,
          ),
        ),
        title: Text(number, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_fmtDate(callTime)}  •  ${_fmtDur(duration)}',
                style: const TextStyle(fontSize: 12)),
            if (hasRecording)
              Row(children: [
                Icon(Icons.mic, size: 12, color: Colors.redAccent.shade100),
                const SizedBox(width: 3),
                Text('Recording saved', style: TextStyle(fontSize: 11, color: Colors.redAccent.shade100)),
              ]),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasRecording)
              IconButton(
                icon: Icon(thisPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: Colors.lightBlueAccent, size: 28),
                onPressed: () => _togglePlay(log),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
              onPressed: () => _delete(log),
            ),
          ],
        ),
      ),
    );
  }
}
