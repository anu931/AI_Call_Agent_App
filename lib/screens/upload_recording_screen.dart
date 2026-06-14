// lib/screens/upload_recording_screen.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import 'dart:io';

class UploadRecordingScreen extends StatefulWidget {
  const UploadRecordingScreen({super.key});

  @override
  State<UploadRecordingScreen> createState() => _UploadRecordingScreenState();
}

class _UploadRecordingScreenState extends State<UploadRecordingScreen> {
  File? _file;
  bool _uploading = false;
  String _status = 'Pick a call recording from your phone storage';
  Map<String, dynamic>? _result;
  final _nameController = TextEditingController(text: 'Unknown');
  final _numberController = TextEditingController();

  Future<void> _pickFile() async {
    // Try audio permission first (Android 13+), fall back to storage
    var status = await Permission.audio.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    // If still denied → guide user to Settings
    if (!status.isGranted) {
      setState(() => _status = '⚠️ Permission denied. Please enable Storage in App Settings.');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text('Storage access is needed to pick call recordings. Please enable it in App Settings.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                onPressed: () { Navigator.pop(context); openAppSettings(); },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'amr', 'ogg', 'aac', 'wav', 'mp4', '3gp'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _file = File(result.files.single.path!);
        _status = '✅ Selected: ${result.files.single.name}';
        _result = null;
      });
    }
  }

  Future<void> _upload() async {
    if (_file == null) return;

    setState(() {
      _uploading = true;
      _status = '⬆️ Uploading file...';
      _result = null;
    });

    // Show live status updates while polling happens inside ApiService
    Future.delayed(const Duration(seconds: 4), () {
      if (_uploading && mounted) setState(() => _status = '🔄 File uploaded. AI is transcribing...');
    });
    Future.delayed(const Duration(seconds: 20), () {
      if (_uploading && mounted) setState(() => _status = '🧠 Transcription done. Analyzing sentiment & issues...');
    });
    Future.delayed(const Duration(seconds: 50), () {
      if (_uploading && mounted) setState(() => _status = '⏳ Almost done, finalizing results...');
    });

    final res = await ApiService.uploadRecording(
      filePath: _file!.path,
      number: _numberController.text.trim().isEmpty ? 'Unknown' : _numberController.text.trim(),
      name: _nameController.text.trim().isEmpty ? 'Unknown' : _nameController.text.trim(),
    );

    setState(() {
      _uploading = false;
      _result = res;
      _status = res.containsKey('error')
          ? '❌ ${res['error']}'
          : '✅ Analysis complete!';
    });
  }

  // ── Helpers to safely read result fields ──────────────────────────────────

  String _getText(String key) {
    final val = _result?[key];
    if (val == null) return '';
    return val.toString();
  }

  String _getSentiment() {
    // DB stores sentiment directly on call_analysis row
    return _getText('sentiment');
  }

  String _getSummary() => _getText('summary');

  String _getTranscript() {
    final t = _result?['transcript'];
    if (t == null) return '';
    if (t is List) return t.map((s) => s['text'] ?? s.toString()).join(' ');
    return t.toString();
  }

  String _getIssue() {
    final issue = _result?['issue'];
    if (issue == null) return '';
    return '${issue['title'] ?? ''}: ${issue['description'] ?? ''}';
  }

  Color _sentimentColor(String s) {
    switch (s.toLowerCase()) {
      case 'positive': return Colors.green;
      case 'negative': return Colors.red;
      default: return Colors.orange;
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Call Recording')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Contact fields
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Contact Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numberController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),

            // Status message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status, style: const TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 12),

            // Pick file button
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.audio_file),
              label: const Text('Pick Recording File'),
            ),
            const SizedBox(height: 8),

            // Upload button
            ElevatedButton.icon(
              onPressed: (_file != null && !_uploading) ? _upload : null,
              icon: _uploading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_uploading ? 'Processing...' : 'Upload & Analyze'),
            ),

            // Loading bar while processing
            if (_uploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'This may take 1–3 minutes depending on recording length.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],

            // ── Results ───────────────────────────────────────────────────
            if (_result != null && !_result!.containsKey('error')) ...[
              const SizedBox(height: 24),
              const Divider(),
              const Text('AI Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Sentiment badge
              if (_getSentiment().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _sentimentColor(_getSentiment()).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _sentimentColor(_getSentiment())),
                  ),
                  child: Text(
                    'Sentiment: ${_getSentiment().toUpperCase()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _sentimentColor(_getSentiment()),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Summary
              if (_getSummary().isNotEmpty)
                _ResultCard(label: '📋 Summary', value: _getSummary()),

              // Issue
              if (_getIssue().isNotEmpty)
                _ResultCard(label: '⚠️ Issue Detected', value: _getIssue()),

              // Transcript
              if (_getTranscript().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('📝 Full Transcript',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_getTranscript(),
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              ],
            ],

            // Error display
            if (_result != null && _result!.containsKey('error')) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Text(
                  _result!['error'].toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String label;
  final String value;
  const _ResultCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }
}