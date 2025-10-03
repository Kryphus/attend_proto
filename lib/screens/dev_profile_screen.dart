import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../services/logging_service.dart';
import '../services/metrics_service.dart';
import '../sync/sync_service.dart';

/// Developer/Debug screen for observability
/// 
/// Shows:
/// - Real-time metrics counters
/// - Log dump functionality
/// - Manual sync trigger
/// - Reset counters
class DevProfileScreen extends StatefulWidget {
  final SyncService syncService;

  const DevProfileScreen({
    super.key,
    required this.syncService,
  });

  @override
  State<DevProfileScreen> createState() => _DevProfileScreenState();
}

class _DevProfileScreenState extends State<DevProfileScreen> {
  Timer? _refreshTimer;
  List<MetricSnapshot> _metrics = [];
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadMetrics() {
    setState(() {
      _metrics = metrics.getAllMetrics();
    });
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _loadMetrics();
      });
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefresh = !_autoRefresh;
    });
    _startAutoRefresh();
  }

  Future<void> _dumpLogs() async {
    final logsJson = logger.getLogsAsJson(100);
    await Clipboard.setData(ClipboardData(text: logsJson));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Last 100 logs copied to clipboard!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _exportMetrics() async {
    final metricsJson = metrics.toJson();
    await Clipboard.setData(ClipboardData(text: metricsJson));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Metrics exported to clipboard!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetCounters() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset All Counters?'),
        content: const Text('This will reset all metric counters to zero. Logs will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              metrics.resetAll();
              _loadMetrics();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All counters reset!'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs?'),
        content: const Text('This will delete all stored logs. Metrics will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              logger.clearLogs();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All logs cleared!'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerSync() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Triggering sync...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      await widget.syncService.syncNow();
      await widget.syncService.reconcileNow();
      
      _loadMetrics();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync completed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group metrics by category
    final captureMetrics = _metrics.where((m) => m.name.startsWith('capture.')).toList();
    final ruleMetrics = _metrics.where((m) => m.name.startsWith('rule.')).toList();
    final outboxMetrics = _metrics.where((m) => m.name.startsWith('outbox.')).toList();
    final syncMetrics = _metrics.where((m) => m.name.startsWith('sync.')).toList();
    final eventMetrics = _metrics.where((m) => m.name.startsWith('event.')).toList();
    final apiMetrics = _metrics.where((m) => m.name.startsWith('api.')).toList();
    final reconcileMetrics = _metrics.where((m) => m.name.startsWith('reconcile.')).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dev Profile'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_autoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAutoRefresh,
            tooltip: _autoRefresh ? 'Pause auto-refresh' : 'Resume auto-refresh',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMetrics,
            tooltip: 'Refresh metrics',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action Buttons
            _buildActionButtons(),
            const SizedBox(height: 24),

            // Summary Stats
            _buildSummaryStats(),
            const SizedBox(height: 24),

            // Metrics by Category
            if (captureMetrics.isNotEmpty) ...[
              _buildMetricsSection('📥 Capture', captureMetrics, Colors.blue),
              const SizedBox(height: 16),
            ],
            
            if (ruleMetrics.isNotEmpty) ...[
              _buildMetricsSection('✅ Rules', ruleMetrics, Colors.green),
              const SizedBox(height: 16),
            ],
            
            if (outboxMetrics.isNotEmpty) ...[
              _buildMetricsSection('📤 Outbox', outboxMetrics, Colors.orange),
              const SizedBox(height: 16),
            ],
            
            if (syncMetrics.isNotEmpty) ...[
              _buildMetricsSection('🔄 Sync', syncMetrics, Colors.teal),
              const SizedBox(height: 16),
            ],
            
            if (eventMetrics.isNotEmpty) ...[
              _buildMetricsSection('📊 Events', eventMetrics, Colors.purple),
              const SizedBox(height: 16),
            ],
            
            if (apiMetrics.isNotEmpty) ...[
              _buildMetricsSection('🌐 API', apiMetrics, Colors.indigo),
              const SizedBox(height: 16),
            ],
            
            if (reconcileMetrics.isNotEmpty) ...[
              _buildMetricsSection('🔁 Reconcile', reconcileMetrics, Colors.cyan),
              const SizedBox(height: 16),
            ],

            // Empty state
            if (_metrics.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No metrics yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use the app to generate metrics',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _dumpLogs,
                icon: const Icon(Icons.file_download),
                label: const Text('Dump Logs'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _exportMetrics,
                icon: const Icon(Icons.bar_chart),
                label: const Text('Export Metrics'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _triggerSync,
                icon: const Icon(Icons.sync),
                label: const Text('Trigger Sync'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resetCounters,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset Counters'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _clearLogs,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Clear Logs'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStats() {
    final totalEvents = metrics.getCounter(MetricsService.eventPending) +
        metrics.getCounter(MetricsService.eventConfirmed) +
        metrics.getCounter(MetricsService.eventRejected);
    
    final captureSuccess = metrics.getCounter(MetricsService.captureSuccess);
    final captureFailure = metrics.getCounter(MetricsService.captureFailure);
    final captureTotal = captureSuccess + captureFailure;
    final captureSuccessRate = captureTotal > 0 
        ? ((captureSuccess / captureTotal) * 100).toStringAsFixed(1)
        : '0.0';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple, Colors.deepPurple[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Summary',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Events',
                  totalEvents.toString(),
                  Icons.event,
                  Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Success Rate',
                  '$captureSuccessRate%',
                  Icons.check_circle,
                  Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Pending',
                  metrics.getCounter(MetricsService.eventPending).toString(),
                  Icons.schedule,
                  Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Synced',
                  metrics.getCounter(MetricsService.outboxSyncSuccess).toString(),
                  Icons.cloud_done,
                  Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withAlpha(204),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsSection(String title, List<MetricSnapshot> sectionMetrics, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(77), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sectionMetrics.map((metric) => _buildMetricRow(metric, color)),
        ],
      ),
    );
  }

  Widget _buildMetricRow(MetricSnapshot metric, Color color) {
    final shortName = metric.name.split('.').last.replaceAll('_', ' ');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shortName,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              metric.value.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

