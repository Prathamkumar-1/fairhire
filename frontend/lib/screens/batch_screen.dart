import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/analysis_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _api = const ApiService();

  Uint8List? _zipBytes;
  String? _zipFilename;
  final _targetCtrl = TextEditingController();
  final _positiveLabelCtrl = TextEditingController(text: '1');
  final _attrsCtrl = TextEditingController(text: 'gender');

  bool _running = false;
  List<BatchSummary>? _results;
  String? _error;

  @override
  void dispose() {
    _targetCtrl.dispose();
    _positiveLabelCtrl.dispose();
    _attrsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _zipBytes = result.files.first.bytes;
      _zipFilename = result.files.first.name;
      _results = null;
      _error = null;
    });
  }

  Future<void> _runBatch() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _zipBytes == null) return;

    final target = _targetCtrl.text.trim();
    final positive = _positiveLabelCtrl.text.trim();
    final attrs = _attrsCtrl.text
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();

    if (target.isEmpty || attrs.isEmpty || positive.isEmpty) {
      setState(() => _error = 'Please fill in all configuration fields.');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _results = null;
    });

    try {
      final results = await _api.batchAnalyze(
        zipBytes: _zipBytes!,
        filename: _zipFilename!,
        userId: user.uid,
        targetColumn: target,
        protectedAttributes: attrs,
        positiveLabel: positive,
      );
      setState(() => _results = results);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Upload'),
        leading: BackButton(onPressed: () => context.go('/dashboard')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Batch Analysis',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                const Text(
                  'Upload a ZIP archive containing multiple CSV files. '
                  'All files will be analysed with the same configuration.',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),

                // ZIP picker
                GestureDetector(
                  onTap: _pickZip,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 36, horizontal: 24),
                    decoration: BoxDecoration(
                      color: _zipBytes != null
                          ? AppColors.success.withOpacity(0.05)
                          : AppColors.primary.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _zipBytes != null
                            ? AppColors.success
                            : AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _zipBytes != null
                              ? Icons.folder_zip
                              : Icons.folder_zip_outlined,
                          size: 44,
                          color: _zipBytes != null
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _zipBytes != null
                              ? _zipFilename!
                              : 'Click to select a ZIP archive',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _zipBytes != null
                                ? AppColors.success
                                : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _zipBytes != null
                              ? '${(_zipBytes!.length / 1024).toStringAsFixed(0)} KB'
                              : 'Contains .csv files. Max 20 files processed.',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Config fields
                TextField(
                  controller: _targetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target column *',
                    hintText: 'e.g. hired',
                    prefixIcon: Icon(Icons.arrow_circle_right_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _attrsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Protected attributes (comma-separated) *',
                    hintText: 'e.g. gender, race, age',
                    prefixIcon: Icon(Icons.people_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _positiveLabelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Positive outcome label *',
                    hintText: 'e.g. 1, yes, hired',
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                ),
                const SizedBox(height: 24),

                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.danger, fontSize: 13))),
                    ]),
                  ),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (!_running && _zipBytes != null) ? _runBatch : null,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_circle_outline),
                    label: Text(_running ? 'Analysing...' : 'Run Batch Analysis'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),

                if (_results != null) ...[
                  const SizedBox(height: 28),
                  Text(
                    'Results — ${_results!.length} file${_results!.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  ..._results!.map((r) => _BatchResultTile(summary: r)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchResultTile extends StatelessWidget {
  final BatchSummary summary;
  const _BatchResultTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    final hasError = summary.error != null;
    final scoreColor = hasError
        ? AppColors.textSecondary
        : AppColors.scoreColor(summary.fairnessScore);
    final verdictColor = AppColors.verdictColor(summary.verdict);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scoreColor.withOpacity(0.1),
            border: Border.all(color: scoreColor, width: 2),
          ),
          child: Center(
            child: hasError
                ? const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 20)
                : Text(
                    summary.fairnessScore.toStringAsFixed(0),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: scoreColor),
                  ),
          ),
        ),
        title: Text(summary.filename,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: hasError
            ? Text(summary.error!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.danger))
            : summary.atRiskFeatures.isNotEmpty
                ? Text('Risk: ${summary.atRiskFeatures.join(', ')}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.warning))
                : const Text('No issues detected',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.success)),
        trailing: summary.verdict != null
            ? Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: verdictColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: verdictColor.withOpacity(0.4)),
                ),
                child: Text(summary.verdict!,
                    style: TextStyle(
                        color: verdictColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              )
            : null,
        onTap: summary.auditId.isNotEmpty
            ? () => context.go('/report/${summary.auditId}')
            : null,
      ),
    );
  }
}
