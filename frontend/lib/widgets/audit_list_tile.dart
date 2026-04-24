import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/analysis_models.dart';
import '../theme/app_theme.dart';

class AuditListTile extends StatelessWidget {
  final AnalysisSummary summary;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const AuditListTile({
    super.key,
    required this.summary,
    this.onTap,
    this.onDelete,
  });

  String _formatTimestamp(String ts) {
    try {
      final dt = DateTime.parse(ts).toLocal();
      return DateFormat('MMM d, y • h:mm a').format(dt);
    } catch (_) {
      return ts;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scoreColor = AppColors.scoreColor(summary.fairnessScore);
    final verdictColor = AppColors.verdictColor(summary.verdict);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Score ring (mini)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoreColor.withOpacity(0.1),
                  border: Border.all(color: scoreColor, width: 2.5),
                ),
                child: Center(
                  child: Text(
                    summary.fairnessScore.toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.datasetFilename ?? 'Untitled Analysis',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatTimestamp(summary.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (summary.atRiskFeatures.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 12, color: AppColors.warning),
                          const SizedBox(width: 3),
                          Text(
                            'Risk: ${summary.atRiskFeatures.join(', ')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Verdict badge
              if (summary.verdict != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: verdictColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: verdictColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    summary.verdict!,
                    style: TextStyle(
                      color: verdictColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
