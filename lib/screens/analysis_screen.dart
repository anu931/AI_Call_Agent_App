import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AnalysisScreen extends StatefulWidget {
  final int callLogId;
  final String phoneNumber;

  const AnalysisScreen({
    super.key,
    required this.callLogId,
    required this.phoneNumber,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  static const _base = 'http://192.168.1.6:8000';

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnalysis();
  }

  Future<void> _fetchAnalysis() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http
          .get(Uri.parse('$_base/calls/analysis/${widget.callLogId}'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        setState(() { _data = jsonDecode(res.body); _loading = false; });
      } else if (res.statusCode == 404) {
        setState(() { _error = 'Analysis not ready yet.\nTry again in a few seconds.'; _loading = false; });
      } else {
        setState(() { _error = 'Server error ${res.statusCode}'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Could not reach backend.\n$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.phoneNumber),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAnalysis),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _fetchAnalysis)
              : _AnalysisBody(data: _data!),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnalysisBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final status     = data['status'] as String? ?? 'unknown';
    final sentiment  = data['sentiment'] as String? ?? 'neutral';
    final score      = (data['sentiment_score'] as num?)?.toDouble() ?? 0.0;
    final summary    = data['summary'] as String? ?? '';
    final issue      = data['issue'] as Map<String, dynamic>?;
    final transcript = data['transcript'] as List<dynamic>? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (status != 'done') _StatusBanner(status: status),
        _SentimentCard(sentiment: sentiment, score: score),
        const SizedBox(height: 12),
        if (issue != null) _IssueCard(issue: issue),
        const SizedBox(height: 12),
        if (summary.isNotEmpty) _SummaryCard(summary: summary),
        const SizedBox(height: 12),
        if (transcript.isNotEmpty) _TranscriptCard(segments: transcript),
      ],
    );
  }
}

class _SentimentCard extends StatelessWidget {
  final String sentiment;
  final double score;
  const _SentimentCard({required this.sentiment, required this.score});

  @override
  Widget build(BuildContext context) {
    final color = switch (sentiment) {
      'positive' => Colors.green,
      'negative' => Colors.red,
      _          => Colors.orange,
    };
    final icon = switch (sentiment) {
      'positive' => Icons.sentiment_very_satisfied,
      'negative' => Icons.sentiment_very_dissatisfied,
      _          => Icons.sentiment_neutral,
    };
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Customer Sentiment',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
            Text(
              sentiment[0].toUpperCase() + sentiment.substring(1),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            Text('Score: ${score.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final Map<String, dynamic> issue;
  const _IssueCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    final count = issue['count'] as int? ?? 1;
    final title = issue['title'] as String? ?? '';
    final desc  = issue['description'] as String? ?? '';
    final last  = issue['last_seen'] as String? ?? '';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bug_report_outlined, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Issue Detected',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: count > 3 ? Colors.red.shade900 : Colors.blueGrey.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count report${count == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
          if (last.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Last seen: $last', style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ]),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.summarize_outlined, size: 18, color: Colors.lightBlueAccent),
            const SizedBox(width: 6),
            Text('Summary',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          Text(summary, style: const TextStyle(fontSize: 14, height: 1.5)),
        ]),
      ),
    );
  }
}

class _TranscriptCard extends StatefulWidget {
  final List<dynamic> segments;
  const _TranscriptCard({required this.segments});

  @override
  State<_TranscriptCard> createState() => _TranscriptCardState();
}

class _TranscriptCardState extends State<_TranscriptCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final shown = _expanded ? widget.segments : widget.segments.take(6).toList();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.record_voice_over_outlined, size: 18, color: Colors.lightGreenAccent),
            const SizedBox(width: 6),
            Text('Transcript',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
            const Spacer(),
            Text('${widget.segments.length} segments',
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          ...shown.map((seg) => _SegmentRow(seg: Map<String, dynamic>.from(seg as Map))),
          if (widget.segments.length > 6)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Show less' : 'Show all ${widget.segments.length} segments'),
            ),
        ]),
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final Map<String, dynamic> seg;
  const _SegmentRow({required this.seg});

  @override
  Widget build(BuildContext context) {
    final role    = seg['role'] as String? ?? seg['speaker'] as String? ?? 'SPEAKER';
    final text    = seg['text'] as String? ?? '';
    final start   = (seg['start'] as num?)?.toDouble() ?? 0;
    final isAgent = role == 'AGENT';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          decoration: BoxDecoration(
            color: isAgent ? Colors.blueGrey.shade800 : Colors.teal.shade900,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(children: [
            Text(isAgent ? 'AGENT' : 'CUST',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isAgent ? Colors.lightBlueAccent : Colors.greenAccent,
                )),
            Text(_fmtTime(start), style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
      ]),
    );
  }

  String _fmtTime(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toInt();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'error' ? Colors.red.shade900 : Colors.blueGrey.shade800;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        if (status == 'processing')
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        if (status != 'processing')
          const Icon(Icons.warning_amber, size: 18, color: Colors.amber),
        const SizedBox(width: 10),
        Text('Status: $status', style: const TextStyle(color: Colors.white)),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off, size: 60, color: Colors.grey),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry')),
    ]),
  );
}