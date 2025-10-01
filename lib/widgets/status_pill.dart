import 'package:flutter/material.dart';

/// Color-coded status pill for event statuses
/// 
/// Shows PENDING (yellow), CONFIRMED (green), or REJECTED (red)
/// with optional tooltip showing the server reason.
class StatusPill extends StatelessWidget {
  final String status; // 'PENDING', 'CONFIRMED', 'REJECTED'
  final String? reason;
  final bool showLabel;

  const StatusPill({
    super.key,
    required this.status,
    this.reason,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);
    
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: config.color.withAlpha(38), // 0.15 * 255 = 38
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config.color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 14, color: config.color),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              config.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: config.color,
              ),
            ),
          ],
        ],
      ),
    );

    // Wrap in tooltip if reason is provided
    if (reason != null && reason!.isNotEmpty) {
      return Tooltip(
        message: reason!,
        preferBelow: false,
        verticalOffset: 20,
        child: pill,
      );
    }

    return pill;
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
        return _StatusConfig(
          color: Colors.green[700]!,
          icon: Icons.check_circle,
          label: 'CONFIRMED',
        );
      case 'REJECTED':
        return _StatusConfig(
          color: Colors.red[700]!,
          icon: Icons.cancel,
          label: 'REJECTED',
        );
      case 'PENDING':
      default:
        return _StatusConfig(
          color: Colors.amber[700]!,
          icon: Icons.schedule,
          label: 'PENDING',
        );
    }
  }
}

class _StatusConfig {
  final Color color;
  final IconData icon;
  final String label;

  _StatusConfig({
    required this.color,
    required this.icon,
    required this.label,
  });
}

