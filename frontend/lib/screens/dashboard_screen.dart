import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/analysis_models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/audit_list_tile.dart';
import '../widgets/trend_line_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _api = const ApiService();

  User? get _user => FirebaseAuth.instance.currentUser;

  List<AnalysisSummary> _history = [];
  List<TrendPoint> _trend = [];
  bool _loading = true;
  String? _error;

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getHistory(_user!.uid),
        _api.getTrend(_user!.uid).catchError((_) => <TrendPoint>[]),
      ]);
      setState(() {
        _history = results[0] as List<AnalysisSummary>;
        _trend = results[1] as List<TrendPoint>;
      });
    } catch (e) {
      setState(() => _error = 'Could not load audit history.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward(from: 0);
      }
    }
  }

  int get _totalAudits => _history.length;
  double get _avgScore {
    if (_history.isEmpty) return 0;
    return _history.map((h) => h.fairnessScore).reduce((a, b) => a + b) /
        _history.length;
  }
  int get _issuesFlagged =>
      _history.where((h) => h.verdict == 'FAIL' || h.verdict == 'CAUTION').length;

  Animation<double> _staggeredFade(int index) {
    const count = 6;
    final start = (index / count).clamp(0.0, 0.7);
    final end = ((index + 1) / count).clamp(start + 0.1, 1.0);
    return CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _user?.displayName?.split(' ').first ?? 'there';
    final isNarrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.balance, size: 22),
            SizedBox(width: 8),
            Text('FairHire'),
          ],
        ),
        actions: [
          if (_user?.photoURL != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CircleAvatar(
                backgroundImage: NetworkImage(_user!.photoURL!),
                radius: 16,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'signout') {
                await _auth.signOut();
                if (mounted) context.go('/');
              } else if (value == 'history') {
                context.go('/history');
              } else if (value == 'batch') {
                context.go('/batch');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'history',
                  child: Row(children: [
                    Icon(Icons.history, size: 18),
                    SizedBox(width: 8),
                    Text('Audit History')
                  ])),
              const PopupMenuItem(
                  value: 'batch',
                  child: Row(children: [
                    Icon(Icons.folder_zip_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Batch Upload')
                  ])),
              const PopupMenuItem(
                  value: 'signout',
                  child: Row(children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 8),
                    Text('Sign Out')
                  ])),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome card
                  FadeTransition(
                    opacity: _staggeredFade(0),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.waving_hand,
                                  color: AppColors.primary, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back, $displayName',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const Text(
                                    'Run an audit to detect bias in your hiring data.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stats row
                  FadeTransition(
                    opacity: _staggeredFade(1),
                    child: _loading
                        ? _StatsRowSkeleton(isNarrow: isNarrow)
                        : isNarrow
                            ? Column(children: [
                                _StatCard(
                                  label: 'Total Audits',
                                  value: '$_totalAudits',
                                  icon: Icons.analytics_outlined,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(height: 10),
                                _StatCard(
                                  label: 'Avg. Fairness Score',
                                  value: _totalAudits == 0
                                      ? '—'
                                      : _avgScore.toStringAsFixed(1),
                                  icon: Icons.speed,
                                  color: AppColors.scoreColor(_avgScore),
                                ),
                                const SizedBox(height: 10),
                                _StatCard(
                                  label: 'Issues Flagged',
                                  value: '$_issuesFlagged',
                                  icon: Icons.flag_outlined,
                                  color: _issuesFlagged > 0
                                      ? AppColors.warning
                                      : AppColors.success,
                                ),
                              ])
                            : Row(children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Total Audits',
                                    value: '$_totalAudits',
                                    icon: Icons.analytics_outlined,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Avg. Fairness Score',
                                    value: _totalAudits == 0
                                        ? '—'
                                        : _avgScore.toStringAsFixed(1),
                                    icon: Icons.speed,
                                    color: AppColors.scoreColor(_avgScore),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Issues Flagged',
                                    value: '$_issuesFlagged',
                                    icon: Icons.flag_outlined,
                                    color: _issuesFlagged > 0
                                        ? AppColors.warning
                                        : AppColors.success,
                                  ),
                                ),
                              ]),
                  ),
                  const SizedBox(height: 20),

                  // Trend chart
                  FadeTransition(
                    opacity: _staggeredFade(2),
                    child: _loading
                        ? const _SkeletonCard(height: 220)
                        : _trend.isNotEmpty
                            ? TrendLineChart(points: _trend)
                            : const SizedBox.shrink(),
                  ),
                  if (!_loading && _trend.isNotEmpty) const SizedBox(height: 20),

                  // New audit CTA
                  FadeTransition(
                    opacity: _staggeredFade(3),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.go('/analyze'),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Start New Audit'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Recent audits header
                  FadeTransition(
                    opacity: _staggeredFade(4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Audits',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (_history.length > 5)
                          TextButton(
                            onPressed: () => context.go('/history'),
                            child: const Text('View All'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Recent audits body
                  FadeTransition(
                    opacity: _staggeredFade(5),
                    child: _loading
                        ? const _AuditListSkeleton()
                        : _error != null
                            ? _ErrorCard(message: _error!, onRetry: _loadData)
                            : _history.isEmpty
                                ? _EmptyState()
                                : Column(
                                    children: _history
                                        .take(5)
                                        .map((s) => AuditListTile(
                                              summary: s,
                                              onTap: () => context
                                                  .go('/report/${s.auditId}'),
                                            ))
                                        .toList(),
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shimmer skeleton widgets ──────────────────────────────────────────────────

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + 3 * _ctrl.value, 0),
            end: Alignment(1.5 + 3 * _ctrl.value, 0),
            colors: const [
              Color(0xFFE8E8E8),
              Color(0xFFF4F4F4),
              Color(0xFFE8E8E8),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;
  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        height: height,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShimmerBox(width: 140, height: 14, borderRadius: 4),
            const SizedBox(height: 12),
            Expanded(child: _ShimmerBox(width: double.infinity, height: double.infinity)),
          ],
        ),
      ),
    );
  }
}

class _StatsRowSkeleton extends StatelessWidget {
  final bool isNarrow;
  const _StatsRowSkeleton({required this.isNarrow});

  Widget _card() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerBox(width: 24, height: 24),
              const SizedBox(height: 10),
              _ShimmerBox(width: 60, height: 24, borderRadius: 4),
              const SizedBox(height: 6),
              _ShimmerBox(width: 100, height: 12, borderRadius: 4),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (isNarrow) {
      return Column(children: [
        _card(), const SizedBox(height: 10), _card(), const SizedBox(height: 10), _card(),
      ]);
    }
    return Row(children: [
      Expanded(child: _card()),
      const SizedBox(width: 12),
      Expanded(child: _card()),
      const SizedBox(width: 12),
      Expanded(child: _card()),
    ]);
  }
}

class _AuditListSkeleton extends StatelessWidget {
  const _AuditListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (_) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _ShimmerBox(width: 52, height: 52, borderRadius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(width: double.infinity, height: 14, borderRadius: 4),
                    const SizedBox(height: 6),
                    _ShimmerBox(width: 140, height: 12, borderRadius: 4),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ShimmerBox(width: 52, height: 26, borderRadius: 6),
            ],
          ),
        ),
      )),
    );
  }
}

// ── Other widgets ─────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 10),
            Text(value,
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
                child: Text(message,
                    style: const TextStyle(color: AppColors.textPrimary))),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 56,
                color: AppColors.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 12),
            const Text('No audits yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            const Text('Start your first bias audit to see results here.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
