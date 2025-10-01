import 'package:flutter/material.dart';
import '../data/local/db.dart';
import 'status_pill.dart';

/// Displays a list of recent attendance events with status pills
/// 
/// Shows event type, timestamp, and current status (PENDING/CONFIRMED/REJECTED).
/// Events can be tapped to view details including server rejection reasons.
class EventHistoryList extends StatelessWidget {
  final List<EventLogData> events;
  final Function(EventLogData)? onEventTap;
  final int maxEvents;

  const EventHistoryList({
    super.key,
    required this.events,
    this.onEventTap,
    this.maxEvents = 20,
  });

  @override
  Widget build(BuildContext context) {
    final displayEvents = events.take(maxEvents).toList();

    if (displayEvents.isEmpty) {
      return Container(
        width: double.infinity,
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
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Colors.grey[400], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Event History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.inbox, color: Colors.grey[400], size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'No events yet',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
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
          Row(
            children: [
              Icon(Icons.history, color: Colors.purple[600], size: 20),
              const SizedBox(width: 8),
              Text(
                'Event History',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Text(
                '${displayEvents.length} event${displayEvents.length > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...displayEvents.map((event) => _buildEventItem(context, event)),
        ],
      ),
    );
  }

  Widget _buildEventItem(BuildContext context, EventLogData event) {
    return InkWell(
      onTap: onEventTap != null ? () => onEventTap!(event) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          children: [
            // Event type icon
            _buildEventIcon(event.type),
            const SizedBox(width: 12),
            
            // Event details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatEventType(event.type),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(event.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            
            // Status pill
            StatusPill(
              status: event.status,
              reason: event.serverReason,
              showLabel: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'ATTEND_IN':
        icon = Icons.login;
        color = Colors.green[600]!;
        break;
      case 'ATTEND_OUT':
        icon = Icons.logout;
        color = Colors.orange[600]!;
        break;
      case 'HEARTBEAT':
        icon = Icons.favorite;
        color = Colors.blue[600]!;
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey[600]!;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(38), // 0.15 * 255 = 38
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  String _formatEventType(String type) {
    switch (type) {
      case 'ATTEND_IN':
        return 'Sign In';
      case 'ATTEND_OUT':
        return 'Sign Out';
      case 'HEARTBEAT':
        return 'Heartbeat';
      default:
        return type;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    String timeAgo;
    if (diff.inSeconds < 60) {
      timeAgo = '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else {
      timeAgo = '${diff.inDays}d ago';
    }

    final time = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';

    return '$time ($timeAgo)';
  }
}

