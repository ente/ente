import "package:flutter/material.dart";

class ViewerAppBar extends StatelessWidget {
  final bool visible;
  final VoidCallback onBackPressed;
  final List<Widget> actions;
  final Key? toolbarKey;

  const ViewerAppBar({
    required this.visible,
    required this.onBackPressed,
    this.actions = const [],
    this.toolbarKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.6),
                Colors.black.withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.025),
                Colors.transparent,
              ],
              stops: const [0, 0.2, 0.9, 0.95, 1],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: AppBar(
                key: toolbarKey,
                clipBehavior: Clip.none,
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackPressed,
                ),
                actions: actions,
                elevation: 0,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
