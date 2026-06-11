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
    // Request permission
    var status = await Permission.audio.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      setState(() => _status = 'Storage permission denied. Enable in Settings.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'amr', 'ogg', 'aac', 'wav', 'mp4', '3gp'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _file = File(result.files.single.path!);
        _status = 'Selected: ${result.files.single.name}';
        _result = null;
      });
    }
  }

  Future<void> _upload() async {
    if (_file == null) return;
    setState(() { _uploading = true; _status = 'Uploading and analyzing...'; });

    final res = await ApiService.uploadRecording(
      filePath: _file!.path,
      number: _numberController.text.trim().isEmpty ? 'Unknown' : _numberController.text.trim(),
      name: _nameController.text.trim().isEmpty ? 'Unknown' : _nameController.text.trim(),
    );

    setState(() {
      _uploading = false;
      _result = res;
      _status = res.containsKey('error') ? 'Error: ${res['error']}' : 'Analysis complete!';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Call Recording')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Contact Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _numberController,
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.audio_file),
              label: const Text('Pick Recording File'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: (_file != null && !_uploading) ? _upload : null,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('Upload & Analyze'),
            ),
            if (_result != null && !_result!.containsKey('error')) ...[
              const SizedBox(height: 24),
              const Divider(),
              const Text('AI Analysis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _ResultCard(label: 'Summary', value: _result!['summary'] ?? ''),
              _ResultCard(label: 'Sentiment', value: _result!['analysis']?['sentiment'] ?? ''),
              _ResultCard(label: 'Priority', value: _result!['analysis']?['priority'] ?? ''),
              _ResultCard(
                label: 'Follow-up Actions',
                value: (_result!['analysis']?['follow_up_actions'] as List?)?.join('\n• ') ?? '',
              ),
              const SizedBox(height: 12),
              const Text('Full Transcript', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_result!['transcript'] ?? '', style: const TextStyle(fontSize: 13)),
            ]
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
    if (value.isEmpty) return const SizedBox();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(value.startsWith('• ') ? value : value),
      ),
    );
  }
}