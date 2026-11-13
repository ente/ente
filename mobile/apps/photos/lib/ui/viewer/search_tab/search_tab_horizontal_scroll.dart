import "package:flutter/material.dart";

const searchTabSectionHorizontalPadding = 15.0;

class SearchTabHorizontalRow extends StatelessWidget {
  const SearchTabHorizontalRow({
    required this.children,
    required this.spacing,
    super.key,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: searchTabSectionHorizontalPadding,
      ),
      physics: const BouncingScrollPhysics(),
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _spacedChildren(),
      ),
    );
  }

  List<Widget> _spacedChildren() {
    return [
      for (final (index, child) in children.indexed) ...[
        if (index != 0) SizedBox(width: spacing),
        child,
      ],
    ];
  }
}

class SearchTabHorizontalScrollView extends StatelessWidget {
  const SearchTabHorizontalScrollView({
    required this.height,
    required this.child,
    super.key,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: searchTabSectionHorizontalPadding,
        ),
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );
  }
}
