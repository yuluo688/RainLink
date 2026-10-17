import 'package:flutter/material.dart';

class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.title,
    required this.description,
    this.leading,
    super.key,
  });

  final String title;
  final String description;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
    return leading == null
        ? titleBlock
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading ?? const SizedBox.shrink(),
            const SizedBox(width: 12),
            Expanded(child: titleBlock),
          ]);
  }
}
