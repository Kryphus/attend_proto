import 'package:flutter/material.dart';

/// Banner that appears at the top of the screen when offline
/// 
/// Shows a prominent message indicating offline mode and that
/// events will sync when connectivity is restored.
class OfflineBanner extends StatelessWidget {
  final VoidCallback? onDismiss;

  const OfflineBanner({
    super.key,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange[700],
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(26), // 0.1 * 255 = 26
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(
                Icons.cloud_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Offline Mode - Events will sync when online',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

