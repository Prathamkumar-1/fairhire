import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/analysis_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bias_bar_chart.dart';
import '../widgets/fairness_score_ring.dart';
import '../widgets/gemini_advisor_card.dart';
import '../widgets/metric_row.dart';

// ── Standalone screen (loads by audit ID) ────────────────────────────────────

class ReportScreen extends StatefulWidget {
  final String auditId;
  const ReportScreen({super.key, required this.auditId});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _api = const ApiService();
  AnalysisResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    try {
      final r = await _api.getReport(widget.auditId);
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load report: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Report'),
        leading: BackButton(onPressed: () => context.go('/history')),
        actions: [
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(context, _result!),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: () => context.go('/history'),
                          child: const Text('Back to History')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: ReportContent(result: _result!),
                    ),
                  ),
                ),
    );
  }
}

// ── PDF export ────────────────────────────────────────────────────────────────

Future<void> _exportPdf(BuildContext context, AnalysisResult result) async {
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('FairHire Audit Report',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                DateFormat('MMMM d, y').format(
                  DateTime.tryParse(result.timestamp)?.toLocal() ??
                      DateTime.now(),
                ),
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(result.datasetFilename ?? 'Analysis',
              style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
          pw.Divider(),
        ],
      ),
      build: (ctx) => [
        // Score + verdict
        pw.Row(children: [
          pw.Container(
            width: 80,
            height: 80,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: PdfColors.blue800, width: 4),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              result.fairnessScore.toStringAsFixed(0),
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800),
            ),
          ),
          pw.SizedBox(width: 20),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Fairness Score: ${result.fairnessScore.toStringAsFixed(1)} / 100',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                if (result.verdict != null)
                  pw.Text('Verdict: ${result.verdict}',
                      style: const pw.TextStyle(fontSize: 13)),
                if (result.verdictReason != null)
                  pw.Text(result.verdictReason!,
                      style: const pw.TextStyle(
                          fontSize: 11, color: PdfColors.grey600)),
              ],
            ),
          ),
        ]),
        pw.SizedBox(height: 16),

        // At-risk features
        if (result.atRiskFeatures.isNotEmpty) ...[
          pw.Text('At-risk attributes: ${result.atRiskFeatures.join(', ')}',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red700)),
          pw.SizedBox(height: 12),
        ],

        // Gemini explanation
        pw.Text('AI Fairness Advisor Summary',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text(result.geminiExplanation,
            style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
        pw.SizedBox(height: 12),

        // Recommendations
        pw.Text('Recommendations',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        ...result.geminiRecommendations.asMap().entries.map((e) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '${e.key + 1}. ${e.value}',
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
              ),
            )),
        pw.SizedBox(height: 12),

        // Metrics table
        pw.Text('Detailed Metrics',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(1.5),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: ['Metric', 'Value', 'Threshold', 'Status'].map((h) =>
                pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(h,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                )).toList(),
            ),
            ...result.metrics.map((m) => pw.TableRow(
                  children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(m.name,
                            style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(m.value.toStringAsFixed(4),
                            style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('${m.threshold}',
                            style: const pw.TextStyle(fontSize: 9))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          m.passed ? 'PASS' : 'FAIL',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: m.passed ? PdfColors.green700 : PdfColors.red700,
                          ),
                        )),
                  ],
                )),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (format) => doc.save(),
    name: 'fairhire_${result.auditId.substring(0, 8)}.pdf',
  );
}

// ── Reusable report content ───────────────────────────────────────────────────

class ReportContent extends StatelessWidget {
  final AnalysisResult result;

  const ReportContent({super.key, required this.result});

  String _formattedDate() {
    try {
      final dt = DateTime.parse(result.timestamp).toLocal();
      return DateFormat('MMMM d, y • h:mm a').format(dt);
    } catch (_) {
      return result.timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroSection(result: result, formattedDate: _formattedDate()),
        const SizedBox(height: 20),
        GeminiAdvisorCard(
          explanation: result.geminiExplanation,
          urgentIssues: result.urgentIssues ?? [],
          recommendations: result.geminiRecommendations,
        ),
        const SizedBox(height: 20),
        _MetricsSection(metrics: result.metrics),
        if (result.intersectionalMetrics?.isNotEmpty == true) ...[
          const SizedBox(height: 20),
          _MetricsSection(
            metrics: result.intersectionalMetrics!,
            title: 'Intersectional Bias Metrics',
            subtitle: 'Metrics computed on combined group intersections.',
          ),
        ],
        const SizedBox(height: 20),
        if (result.chartData.isNotEmpty) ...[
          _ChartsSection(chartData: result.chartData),
          const SizedBox(height: 20),
        ],
        _ActionsSection(result: result),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Hero Section ──────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final AnalysisResult result;
  final String formattedDate;

  const _HeroSection({required this.result, required this.formattedDate});

  @override
  Widget build(BuildContext context) {
    final verdictColor = AppColors.verdictColor(result.verdict);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                FairnessScoreRing(score: result.fairnessScore, size: 140),
                const SizedBox(height: 8),
                const Text('Fairness Score',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.datasetFilename ?? 'Audit Report',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(formattedDate,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                  if (result.verdict != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: verdictColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: verdictColor.withOpacity(0.4), width: 1.5),
                      ),
                      child: Text(
                        result.verdict!,
                        style: TextStyle(
                          color: verdictColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  if (result.verdictReason != null) ...[
                    const SizedBox(height: 8),
                    Text(result.verdictReason!,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4)),
                  ],
                  if (result.atRiskFeatures.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('At-risk attributes:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: result.atRiskFeatures
                          .map((f) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(f,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w600)),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Metrics Section ───────────────────────────────────────────────────────────

class _MetricsSection extends StatelessWidget {
  final List<BiasMetric> metrics;
  final String title;
  final String subtitle;

  const _MetricsSection({
    required this.metrics,
    this.title = 'Detailed Metrics',
    this.subtitle = 'Tap any row for a full description.',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.table_chart_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ]),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: const [
                  SizedBox(width: 34),
                  SizedBox(width: 12),
                  Expanded(
                      flex: 4,
                      child: Text('Metric',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppColors.textSecondary))),
                  Expanded(
                      flex: 2,
                      child: Text('Value',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.center)),
                  Expanded(
                      flex: 2,
                      child: Text('Threshold',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.center)),
                  SizedBox(width: 60),
                  SizedBox(width: 22),
                ],
              ),
            ),
            const Divider(height: 1),
            ...metrics.map((m) => Column(children: [
                  MetricRow(
                    metric: m,
                    onTap: () => _showMetricDetail(context, m),
                  ),
                  const Divider(height: 1, indent: 46),
                ])),
          ],
        ),
      ),
    );
  }

  void _showMetricDetail(BuildContext context, BiasMetric metric) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                metric.passed ? Icons.check_circle : Icons.cancel,
                color: metric.passed ? AppColors.success : AppColors.danger,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(metric.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 16),
            _DetailRow('Value', metric.value.toStringAsFixed(4)),
            _DetailRow('Threshold', '${metric.threshold}'),
            _DetailRow('Status', metric.passed ? 'PASS' : 'FAIL'),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(metric.description,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13))),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}

// ── Charts Section ────────────────────────────────────────────────────────────

class _ChartsSection extends StatelessWidget {
  final Map<String, dynamic> chartData;

  const _ChartsSection({required this.chartData});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(Icons.bar_chart, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text('Selection Rate Charts',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ]),
        ),
        ...chartData.entries.map((entry) {
          final data = entry.value as Map<String, dynamic>;
          final groups = (data['groups'] as List).cast<String>();
          final rates = (data['selection_rates'] as List)
              .map((r) => (r as num).toDouble())
              .toList();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BiasBarChart(
              attributeName: entry.key,
              groups: groups,
              selectionRates: rates,
            ),
          );
        }),
      ],
    );
  }
}

// ── Actions Section ───────────────────────────────────────────────────────────

class _ActionsSection extends StatelessWidget {
  final AnalysisResult result;
  const _ActionsSection({required this.result});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ElevatedButton.icon(
          onPressed: () => _exportPdf(context, result),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Export PDF'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.textPrimary),
        ),
        ElevatedButton.icon(
          onPressed: () => context.go('/analyze'),
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('Run New Audit'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/dashboard'),
          icon: const Icon(Icons.dashboard_outlined),
          label: const Text('Back to Dashboard'),
        ),
      ],
    );
  }
}
