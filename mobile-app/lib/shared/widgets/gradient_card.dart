import 'package:flutter/material.dart';

class GradientCard extends StatelessWidget {
  final LinearGradient gradient;
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const GradientCard({
    super.key,
    required this.gradient,
    required this.child,
    this.borderRadius = 18,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
