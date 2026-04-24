import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/analysis_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'report_screen.dart';

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final _api = const ApiService();
  int _step = 0;

  // Step 1 state
  Uint8List? _fileBytes;
  String? _filename;
  int _rowCount = 0;
  bool _previewing = false;
  PreviewResponse? _preview;

  // Step 2 state
  final _targetCtrl = TextEditingController();
  final _positiveLabelCtrl = TextEditingController(text: '1');
  final _customAttrCtrl = TextEditingController();
  final Set<String> _selectedAttrs = {};
  bool _intersectional = false;
  static const _defaultAttrs = ['gender', 'age', 'race', 'ethnicity', 'disability'];

  // Step 3 state
  bool _analyzing = false;
  int _loadingMsgIdx = 0;
  AnalysisResult? _result;
  bool _step2Valid = false;

  // Error banner state (dismissible)
  String? _bannerError;

  static const _loadingMessages = [
    'Uploading dataset...',
    'Running bias analysis...',
    'Consulting Gemini AI advisor...',
    'Generating your report...',
  ];

  @override
  void initState() {
    super.initState();
    _targetCtrl.addListener(_validateStep2);
    _positiveLabelCtrl.addListener(_validateStep2);
  }

  @override
  void dispose() {
    _targetCtrl.removeListener(_validateStep2);
    _positiveLabelCtrl.removeListener(_validateStep2);
    _targetCtrl.dispose();
    _positiveLabelCtrl.dispose();
    _customAttrCtrl.dispose();
    super.dispose();
  }

  void _validateStep2() {
    final valid = _targetCtrl.text.trim().isNotEmpty &&
        _positiveLabelCtrl.text.trim().isNotEmpty &&
        _selectedAttrs.isNotEmpty;
    if (valid != _step2Valid) setState(() => _step2Valid = valid);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    int rows = 0;
    if (file.bytes != null) {
      try {
        final content = utf8.decode(file.bytes!);
        final lines =
            content.split('\n').where((l) => l.trim().isNotEmpty).toList();
        rows = lines.length > 1 ? lines.length - 1 : 0;
      } catch (_) {}
    }
    setState(() {
      _fileBytes = file.bytes;
      _filename = file.name;
      _rowCount = rows;
      _preview = null;
    });

    // Kick off preview in the background
    if (file.bytes != null) {
      _fetchPreview(file.bytes!, file.name);
    }
  }

  Future<void> _fetchPreview(Uint8List bytes, String filename) async {
    setState(() => _previewing = true);
    try {
      final preview = await _api.previewDataset(fileBytes: bytes, filename: filename);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        // Auto-populate Step 2 fields from suggestions
        if (preview.suggestedTarget != null) {
          _targetCtrl.text = preview.suggestedTarget!;
        }
        if (preview.detectedPositiveLabel != null) {
          _positiveLabelCtrl.text = preview.detectedPositiveLabel!;
        }
        for (final attr in preview.suggestedProtectedAttrs) {
          _selectedAttrs.add(attr);
        }
        _validateStep2();
      });
    } catch (_) {
      // Preview is best-effort; ignore failures
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _runAnalysis() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _fileBytes == null) return;

    setState(() {
      _step = 2;
      _analyzing = true;
      _loadingMsgIdx = 0;
      _result = null;
      _bannerError = null;
    });

    final ticker = Stream.periodic(const Duration(seconds: 2), (i) => i)
        .take(_loadingMessages.length - 1)
        .listen((i) {
      if (mounted) setState(() => _loadingMsgIdx = i + 1);
    });

    try {
      final result = await _api.uploadAndAnalyze(
        fileBytes: _fileBytes!,
        filename: _filename!,
        userId: user.uid,
        targetColumn: _targetCtrl.text.trim(),
        protectedAttributes: _selectedAttrs.toList(),
        positiveLabel: _positiveLabelCtrl.text.trim(),
        intersectional: _intersectional,
      );
      ticker.cancel();
      setState(() {
        _result = result;
        _analyzing = false;
      });
    } on ApiException catch (e) {
      ticker.cancel();
      // Show dismissible banner and send user back to step 2
      setState(() {
        _bannerError = e.message;
        _analyzing = false;
        _step = 1;
      });
    } catch (e) {
      ticker.cancel();
      setState(() {
        _bannerError = e.toString();
        _analyzing = false;
        _step = 1;
      });
    }
  }

  void _addCustomAttr() {
    final val = _customAttrCtrl.text.trim();
    if (val.isNotEmpty) {
      setState(() => _selectedAttrs.add(val));
      _customAttrCtrl.clear();
      _validateStep2();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Audit'),
        leading: BackButton(onPressed: () {
          if (_step > 0 && !_analyzing) {
            setState(() {
              _step = _step - 1;
              _bannerError = null;
            });
          } else {
            context.go('/dashboard');
          }
        }),
      ),
      // Error banner anchored below AppBar
      body: Column(
        children: [
          if (_bannerError != null)
            MaterialBanner(
              backgroundColor: AppColors.danger.withOpacity(0.08),
              leading: const Icon(Icons.error_outline, color: AppColors.danger),
              content: Text(
                _bannerError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _bannerError = null),
                  child: const Text('Dismiss',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ],
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StepIndicator(currentStep: _step),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.05, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                        child: _step == 0
                            ? _buildStep1()
                            : _step == 1
                                ? _buildStep2()
                                : _buildStep3(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Upload Dataset',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Upload a CSV file with your hiring outcome data.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 20),

        GestureDetector(
          onTap: _pickFile,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            decoration: BoxDecoration(
              color: _fileBytes != null
                  ? AppColors.success.withOpacity(0.05)
                  : AppColors.primary.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _fileBytes != null
                    ? AppColors.success
                    : AppColors.primary.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  _fileBytes != null
                      ? Icons.check_circle
                      : Icons.cloud_upload_outlined,
                  size: 48,
                  color: _fileBytes != null ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  _fileBytes != null ? _filename! : 'Click to select a CSV file',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color:
                        _fileBytes != null ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fileBytes != null
                      ? '${(_fileBytes!.length / 1024).toStringAsFixed(1)} KB'
                      : 'Supports .csv files up to 50 MB',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),

        if (_fileBytes != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_chart,
                        color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_filename!,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                            '${(_fileBytes!.length / 1024).toStringAsFixed(1)} KB · $_rowCount rows · CSV',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                        if (_previewing)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Row(children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 6),
                              Text('Detecting columns…',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ]),
                          ),
                        if (_preview != null && !_previewing)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              const Icon(Icons.auto_fix_high,
                                  size: 12, color: AppColors.success),
                              const SizedBox(width: 4),
                              Text(
                                '${_preview!.columnCount} columns detected — fields pre-filled',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.success),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _fileBytes = null;
                      _filename = null;
                      _rowCount = 0;
                      _preview = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _fileBytes != null
                ? () {
                    _validateStep2();
                    setState(() => _step = 1);
                  }
                : null,
            child: const Text('Configure Analysis →'),
          ),
        ),
        const SizedBox(height: 20),
        _CsvFormatHint(),
      ],
    );
  }

  Widget _buildStep2() {
    // Determine available columns for dropdown (from preview if available)
    final previewCols = _preview?.columns ?? [];

    return Column(
      key: const ValueKey('step2'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Configure Analysis',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Tell FairHire what to look for in your dataset.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 24),

        // Target column — dropdown if we have column names, text field otherwise
        if (previewCols.isNotEmpty) ...[
          const Text('Target column *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: previewCols.contains(_targetCtrl.text) ? _targetCtrl.text : null,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.arrow_circle_right_outlined),
              hintText: 'Select the outcome column',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: previewCols
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                _targetCtrl.text = val;
                _validateStep2();
              }
            },
          ),
        ] else
          TextField(
            controller: _targetCtrl,
            decoration: const InputDecoration(
              labelText: 'Target column name *',
              hintText: 'e.g. hired, outcome, selected',
              prefixIcon: Icon(Icons.arrow_circle_right_outlined),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'The column representing the hiring decision (0/1, yes/no, etc.)',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Protected attributes
        const Text('Protected attributes to check *',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        // Show suggested attrs from preview + defaults
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: {
            ..._defaultAttrs,
            ...(_preview?.suggestedProtectedAttrs ?? []),
          }.map((attr) {
            final selected = _selectedAttrs.contains(attr);
            return FilterChip(
              label: Text(attr),
              selected: selected,
              onSelected: (v) {
                setState(() => v ? _selectedAttrs.add(attr) : _selectedAttrs.remove(attr));
                _validateStep2();
              },
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        if (_selectedAttrs.any((a) => !_defaultAttrs.contains(a) &&
            !(_preview?.suggestedProtectedAttrs ?? []).contains(a)))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedAttrs
                  .where((a) => !_defaultAttrs.contains(a) &&
                      !(_preview?.suggestedProtectedAttrs ?? []).contains(a))
                  .map((attr) => Chip(
                        label: Text(attr),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() => _selectedAttrs.remove(attr));
                          _validateStep2();
                        },
                        backgroundColor: AppColors.primary.withOpacity(0.12),
                        labelStyle: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ))
                  .toList(),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customAttrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Add custom attribute',
                  hintText: 'e.g. religion',
                  prefixIcon: Icon(Icons.add),
                  isDense: true,
                ),
                onSubmitted: (_) => _addCustomAttr(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addCustomAttr,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Positive label
        TextField(
          controller: _positiveLabelCtrl,
          decoration: const InputDecoration(
            labelText: 'Positive outcome label *',
            hintText: 'e.g. 1, yes, hired, true',
            prefixIcon: Icon(Icons.check_circle_outline),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The value in your target column that means "hired" or "selected".',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),

        // Intersectional bias toggle
        Card(
          color: AppColors.primary.withOpacity(0.04),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.primary.withOpacity(0.15)),
          ),
          child: SwitchListTile(
            value: _intersectional,
            onChanged: (v) => setState(() => _intersectional = v),
            title: const Text('Intersectional bias analysis',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text(
              'Also compute metrics on combined groups (e.g. gender × race).',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _step2Valid ? _runAnalysis : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline),
                SizedBox(width: 8),
                Text('Run Analysis',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    if (_analyzing) {
      return _LoadingView(
        key: const ValueKey('loading'),
        message: _loadingMessages[_loadingMsgIdx],
        progress: (_loadingMsgIdx + 1) / _loadingMessages.length,
      );
    }
    if (_result != null) {
      return ReportContent(key: const ValueKey('result'), result: _result!);
    }
    return const SizedBox.shrink();
  }
}

// ── Step indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const steps = ['Upload', 'Configure', 'Results'];
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: 2,
              color:
                  i ~/ 2 < currentStep ? AppColors.primary : AppColors.divider,
            ),
          );
        }
        final stepIdx = i ~/ 2;
        final done = stepIdx < currentStep;
        final active = stepIdx == currentStep;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: done
                    ? AppColors.success
                    : active
                        ? AppColors.primary
                        : AppColors.divider,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text('${stepIdx + 1}',
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        )),
              ),
            ),
            const SizedBox(height: 4),
            Text(steps[stepIdx],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? AppColors.primary : AppColors.textSecondary,
                )),
          ],
        );
      }),
    );
  }
}

// ── Loading view ──────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String message;
  final double progress;

  const _LoadingView({super.key, required this.message, required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 3),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              message,
              key: ValueKey(message),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 500),
                builder: (_, value, __) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── CSV hint card ─────────────────────────────────────────────────────────────

class _CsvFormatHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withOpacity(0.04),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.lightbulb_outline, color: AppColors.primary, size: 16),
              SizedBox(width: 6),
              Text('Expected CSV format',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      fontSize: 13)),
            ]),
            SizedBox(height: 8),
            Text(
              'candidate_id, age, gender, years_experience, skills_score, hired\n'
              '1001, 29, Male, 4.5, 82.3, 1\n'
              '1002, 34, Female, 6.0, 79.1, 0\n'
              '...',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
