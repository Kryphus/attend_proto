import 'package:flutter/material.dart';

/// Card displaying sync-related status information
/// 
/// Shows pending event count and last sync timestamp in a
/// Material Design card with icon and formatting.
class EventStatusCard extends StatelessWidget {
  final int pendingCount;
  final DateTime? lastSyncTime;
  final DateTime? lastReconcileTime;

  const EventStatusCard({
    super.key,
    required this.pendingCount,
    this.lastSyncTime,
    this.lastReconcileTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13), // 0.05 * 255 = 13
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pending Count Section
          Row(
            children: [
              Icon(
                Icons.schedule,
                color: pendingCount > 0 ? Colors.amber[700] : Colors.grey[400],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Pending Events',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pendingCount > 0 ? '$pendingCount event${pendingCount > 1 ? 's' : ''}' : 'None',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: pendingCount > 0 ? Colors.amber[700] : Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 16),
          Divider(color: Colors.grey[200], height: 1),
          const SizedBox(height: 16),
          
          // Last Sync Section
          Row(
            children: [
              Icon(
                Icons.sync,
                color: Colors.teal[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Last Sync',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatLastSync(lastSyncTime),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.teal[600],
            ),
          ),
          
          // Reconcile time (if available and different from sync)
          if (lastReconcileTime != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.sync_alt,
                  color: Colors.blue[600],
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Last Reconcile',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatLastSync(lastReconcileTime),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blue[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatLastSync(DateTime? time) {
    if (time == null) {
      return 'Never';
    }

    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 10) {
      return 'Just now';
    } else if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

