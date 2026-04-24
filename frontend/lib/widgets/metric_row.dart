import 'package:flutter/material.dart';

import '../models/analysis_models.dart';
import '../theme/app_theme.dart';

class MetricRow extends StatelessWidget {
  final BiasMetric metric;
  final VoidCallback? onTap;

  const MetricRow({super.key, required this.metric, this.onTap});

  /// Disparate Impact uses "≥" (value must be above threshold).
  /// Difference metrics use "≤" (value must be below threshold).
  String _thresholdLabel() {
    final lower = metric.name.toLowerCase();
    if (lower.contains('disparate impact')) {
      return '≥ ${metric.threshold}';
    }
    return '≤ ${metric.threshold}';
  }

  @override
  Widget build(BuildContext context) {
    final color = metric.passed ? AppColors.success : AppColors.danger;
    final icon = metric.passed ? Icons.check_circle : Icons.cancel;

    // Split "MetricName (attribute)" into parts
    final parts = metric.name.split('(');
    final metricName = parts[0].trim();
    final attrLabel =
        parts.length > 1 ? parts[1].replaceAll(')', '').trim() : '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Status icon
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),

            // Metric name + attribute tag
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metricName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (attrLabel.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        attrLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Value
            Expanded(
              flex: 2,
              child: Text(
                metric.value.toStringAsFixed(4),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Threshold — direction-aware
            Expanded(
              flex: 2,
              child: Text(
                _thresholdLabel(),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Pass/Fail chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                metric.passed ? 'PASS' : 'FAIL',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
