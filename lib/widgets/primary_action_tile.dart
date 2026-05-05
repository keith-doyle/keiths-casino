import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PrimaryActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  const PrimaryActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
//Reusable large navigation action card with icon title subtitle and arrow, dashboard action tile design
  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: primary
              ? Colors.white.withOpacity(0.18)
              : Colors.black.withOpacity(0.05),
          child: Icon(
            icon,
            color: primary
                ? Colors.white
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: primary ? Colors.white : null,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: primary ? Colors.white70 : null,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: primary ? Colors.white70 : Colors.black45,
        ),
      ],
    );

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        decoration: primary
            ? AppTheme.gradientHeroDecoration
            : AppTheme.softCardDecoration,
        padding: const EdgeInsets.all(18),
        child: content,
      ),
    );
  }
}