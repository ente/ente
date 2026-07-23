import 'package:ente_contacts/contacts.dart';
import 'package:ente_sharing/extensions/user_extension.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:flutter/widgets.dart';

typedef ResolvedUserWidgetBuilder =
    Widget Function(
      BuildContext context,
      String displayName,
      String actualEmail,
    );

class ResolvedUserBuilder extends StatelessWidget {
  final User user;
  final ResolvedUserWidgetBuilder builder;

  const ResolvedUserBuilder({
    super.key,
    required this.user,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ContactsDisplayService.instance.changes,
      builder: (context, _, _) =>
          builder(context, user.resolvedDisplayName, user.email),
    );
  }
}
