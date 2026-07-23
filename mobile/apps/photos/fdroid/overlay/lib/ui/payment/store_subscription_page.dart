import "package:flutter/widgets.dart";

class StoreSubscriptionPage extends StatefulWidget {
  final bool isOnboarding;

  const StoreSubscriptionPage({this.isOnboarding = false, super.key});

  @override
  State<StoreSubscriptionPage> createState() => _StoreSubscriptionPageState();
}

class _StoreSubscriptionPageState extends State<StoreSubscriptionPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
