import 'package:flutter/material.dart';

abstract final class WorkspaceColors {
  static const ink = Color(0xff15283f);
  static const muted = Color(0xff6c7b8e);
  static const canvas = Color(0xfff3f5f9);
  static const teal = Color(0xff087f74);
  static const amber = Color(0xffbc7b16);
  static const line = Color(0xffe5eaf1);
}

class WorkspaceCard extends StatelessWidget {
  const WorkspaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: WorkspaceColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class WorkspaceLabel extends StatelessWidget {
  const WorkspaceLabel(
    this.text, {
    super.key,
    this.color = WorkspaceColors.muted,
  });
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.7,
      color: color,
    ),
  );
}

class WorkspaceBadge extends StatelessWidget {
  const WorkspaceBadge(
    this.text, {
    super.key,
    this.color = WorkspaceColors.teal,
    this.icon,
  });
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}
