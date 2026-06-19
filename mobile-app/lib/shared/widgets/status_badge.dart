import 'package:flutter/material.dart';
import '../../core/theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isOnline;

  const StatusBadge({
    super.key,
    required this.status,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = isOnline ? AppTheme.online : AppTheme.offline;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: badgeColor,
            shape: BoxShape.circle,
            boxShadow: [
              if (isOnline)
                BoxShadow(
                  color: badgeColor.withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          status,
          style: TextStyle(
            color: badgeColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
