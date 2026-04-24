class AnalysisRequest {
  final String datasetUrl;
  final String targetColumn;
  final List<String> protectedAttributes;
  final String positiveLabel;
  final String userId;
  final bool intersectional;

  const AnalysisRequest({
    required this.datasetUrl,
    required this.targetColumn,
    required this.protectedAttributes,
    required this.positiveLabel,
    required this.userId,
    this.intersectional = false,
  });

  Map<String, dynamic> toJson() => {
        'dataset_url': datasetUrl,
        'target_column': targetColumn,
        'protected_attributes': protectedAttributes,
        'positive_label': positiveLabel,
        'user_id': userId,
        'intersectional': intersectional,
      };
}

class BiasMetric {
  final String name;
  final double value;
  final double threshold;
  final bool passed;
  final String description;

  const BiasMetric({
    required this.name,
    required this.value,
    required this.threshold,
    required this.passed,
    required this.description,
  });

  factory BiasMetric.fromJson(Map<String, dynamic> json) => BiasMetric(
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
        threshold: (json['threshold'] as num).toDouble(),
        passed: json['passed'] as bool,
        description: json['description'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'threshold': threshold,
        'passed': passed,
        'description': description,
      };
}

class DatasetProfile {
  final int rows;
  final int columns;
  final Map<String, String> columnDtypes;
  final Map<String, double> missingPct;
  final Map<String, double> classDistribution;
  final double classImbalanceRatio;
  final String? detectedTarget;
  final List<String> detectedProtectedAttrs;
  final String? detectedPositiveLabel;

  const DatasetProfile({
    required this.rows,
    required this.columns,
    required this.columnDtypes,
    required this.missingPct,
    required this.classDistribution,
    required this.classImbalanceRatio,
    this.detectedTarget,
    this.detectedProtectedAttrs = const [],
    this.detectedPositiveLabel,
  });

  factory DatasetProfile.fromJson(Map<String, dynamic> json) => DatasetProfile(
        rows: json['rows'] as int,
        columns: json['columns'] as int,
        columnDtypes: Map<String, String>.from(json['column_dtypes'] as Map),
        missingPct: (json['missing_pct'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        classDistribution: (json['class_distribution'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        ),
        classImbalanceRatio: (json['class_imbalance_ratio'] as num).toDouble(),
        detectedTarget: json['detected_target'] as String?,
        detectedProtectedAttrs:
            (json['detected_protected_attrs'] as List?)?.cast<String>() ?? [],
        detectedPositiveLabel: json['detected_positive_label'] as String?,
      );
}

class AnalysisResult {
  final String auditId;
  final String timestamp;
  final double fairnessScore;
  final List<BiasMetric> metrics;
  final String geminiExplanation;
  final List<String> geminiRecommendations;
  final List<String> atRiskFeatures;
  final Map<String, dynamic> chartData;
  final String? verdict;
  final String? verdictReason;
  final List<String>? urgentIssues;
  final String? datasetFilename;
  final DatasetProfile? datasetProfile;
  final List<BiasMetric>? intersectionalMetrics;

  const AnalysisResult({
    required this.auditId,
    required this.timestamp,
    required this.fairnessScore,
    required this.metrics,
    required this.geminiExplanation,
    required this.geminiRecommendations,
    required this.atRiskFeatures,
    required this.chartData,
    this.verdict,
    this.verdictReason,
    this.urgentIssues,
    this.datasetFilename,
    this.datasetProfile,
    this.intersectionalMetrics,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) => AnalysisResult(
        auditId: json['audit_id'] as String,
        timestamp: json['timestamp'] as String,
        fairnessScore: (json['fairness_score'] as num).toDouble(),
        metrics: (json['metrics'] as List)
            .map((m) => BiasMetric.fromJson(m as Map<String, dynamic>))
            .toList(),
        geminiExplanation: json['gemini_explanation'] as String,
        geminiRecommendations:
            (json['gemini_recommendations'] as List).cast<String>(),
        atRiskFeatures: (json['at_risk_features'] as List).cast<String>(),
        chartData: json['chart_data'] as Map<String, dynamic>,
        verdict: json['verdict'] as String?,
        verdictReason: json['verdict_reason'] as String?,
        urgentIssues: (json['urgent_issues'] as List?)?.cast<String>(),
        datasetFilename: json['dataset_filename'] as String?,
        datasetProfile: json['dataset_profile'] == null
            ? null
            : DatasetProfile.fromJson(
                json['dataset_profile'] as Map<String, dynamic>),
        intersectionalMetrics: (json['intersectional_metrics'] as List?)
            ?.map((m) => BiasMetric.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'audit_id': auditId,
        'timestamp': timestamp,
        'fairness_score': fairnessScore,
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'gemini_explanation': geminiExplanation,
        'gemini_recommendations': geminiRecommendations,
        'at_risk_features': atRiskFeatures,
        'chart_data': chartData,
        'verdict': verdict,
        'verdict_reason': verdictReason,
        'urgent_issues': urgentIssues,
        'dataset_filename': datasetFilename,
      };
}

class AnalysisSummary {
  final String auditId;
  final String timestamp;
  final double fairnessScore;
  final String? verdict;
  final String? datasetFilename;
  final List<String> atRiskFeatures;

  const AnalysisSummary({
    required this.auditId,
    required this.timestamp,
    required this.fairnessScore,
    this.verdict,
    this.datasetFilename,
    this.atRiskFeatures = const [],
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) =>
      AnalysisSummary(
        auditId: json['audit_id'] as String,
        timestamp: json['timestamp'] as String,
        fairnessScore: (json['fairness_score'] as num).toDouble(),
        verdict: json['verdict'] as String?,
        datasetFilename: json['dataset_filename'] as String?,
        atRiskFeatures:
            (json['at_risk_features'] as List?)?.cast<String>() ?? [],
      );
}

class PreviewResponse {
  final List<String> columns;
  final Map<String, String> dtypes;
  final Map<String, List<String>> sampleValues;
  final String? suggestedTarget;
  final List<String> suggestedProtectedAttrs;
  final String? detectedPositiveLabel;
  final int rowCount;
  final int columnCount;

  const PreviewResponse({
    required this.columns,
    required this.dtypes,
    required this.sampleValues,
    this.suggestedTarget,
    this.suggestedProtectedAttrs = const [],
    this.detectedPositiveLabel,
    required this.rowCount,
    required this.columnCount,
  });

  factory PreviewResponse.fromJson(Map<String, dynamic> json) =>
      PreviewResponse(
        columns: (json['columns'] as List).cast<String>(),
        dtypes: Map<String, String>.from(json['dtypes'] as Map),
        sampleValues: (json['sample_values'] as Map).map(
          (k, v) => MapEntry(k as String, (v as List).cast<String>()),
        ),
        suggestedTarget: json['suggested_target'] as String?,
        suggestedProtectedAttrs:
            (json['suggested_protected_attrs'] as List?)?.cast<String>() ?? [],
        detectedPositiveLabel: json['detected_positive_label'] as String?,
        rowCount: json['row_count'] as int,
        columnCount: json['column_count'] as int,
      );
}

class TrendPoint {
  final String week;
  final double avgScore;
  final int passCount;
  final int cautionCount;
  final int failCount;

  const TrendPoint({
    required this.week,
    required this.avgScore,
    required this.passCount,
    required this.cautionCount,
    required this.failCount,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        week: json['week'] as String,
        avgScore: (json['avg_score'] as num).toDouble(),
        passCount: json['pass_count'] as int,
        cautionCount: json['caution_count'] as int,
        failCount: json['fail_count'] as int,
      );

  int get totalAudits => passCount + cautionCount + failCount;
}

class BatchSummary {
  final String filename;
  final String auditId;
  final double fairnessScore;
  final String? verdict;
  final List<String> atRiskFeatures;
  final String? error;

  const BatchSummary({
    required this.filename,
    required this.auditId,
    required this.fairnessScore,
    this.verdict,
    this.atRiskFeatures = const [],
    this.error,
  });

  factory BatchSummary.fromJson(Map<String, dynamic> json) => BatchSummary(
        filename: json['filename'] as String,
        auditId: json['audit_id'] as String,
        fairnessScore: (json['fairness_score'] as num).toDouble(),
        verdict: json['verdict'] as String?,
        atRiskFeatures:
            (json['at_risk_features'] as List?)?.cast<String>() ?? [],
        error: json['error'] as String?,
      );
}
