import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/contacts/contact_identity_resolver.dart";
import "package:photos/ui/sharing/share_components.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/sharing/widgets/sharing_role.dart";

class ScrollableParticipantRoster extends StatefulWidget {
  const ScrollableParticipantRoster({super.key, required this.rows});

  final List<Widget> rows;

  @override
  State<ScrollableParticipantRoster> createState() =>
      _ScrollableParticipantRosterState();
}

class _ScrollableParticipantRosterState
    extends State<ScrollableParticipantRoster> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const maxVisibleRows = 3;
    final rowExtent = _rowExtent(context);
    final hasMultipleRows = widget.rows.length > 1;
    final itemSpacing = hasMultipleRows ? Spacing.xs : 0.0;
    final groupPadding = hasMultipleRows ? Spacing.sm : 0.0;
    final visibleRows = math.min(widget.rows.length, maxVisibleRows);
    final viewportHeight =
        visibleRows * rowExtent +
        groupPadding * 2 +
        math.max(0, visibleRows - 1) * itemSpacing;
    final showScrollbar = widget.rows.length > maxVisibleRows;
    final roster = ClipRRect(
      key: const ValueKey("participant-roster-clip"),
      borderRadius: BorderRadius.circular(Radii.button),
      child: ColoredBox(
        color: context.componentColors.fillLight,
        child: ListView.builder(
          key: const ValueKey("participant-roster-scroll"),
          controller: _scrollController,
          primary: false,
          padding: EdgeInsets.only(
            top: groupPadding,
            bottom: groupPadding - itemSpacing,
          ),
          itemCount: widget.rows.length,
          itemExtent: rowExtent + itemSpacing,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(bottom: itemSpacing),
            child: widget.rows[index],
          ),
        ),
      ),
    );
    return SizedBox(
      height: viewportHeight,
      child: showScrollbar
          ? shareScrollbar(
              context,
              key: const ValueKey("participant-roster-scrollbar"),
              controller: _scrollController,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: Spacing.sm + 5),
                child: roster,
              ),
            )
          : roster,
    );
  }

  double _rowExtent(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final titleExtent =
        textScaler.scale(TextStyles.body.fontSize!) * TextStyles.body.height!;
    final roleExtent =
        textScaler.scale(TextStyles.mini.fontSize!) * TextStyles.mini.height!;
    return math.max(68.0, titleExtent + Spacing.xs + roleExtent + 20.0);
  }
}

class ParticipantRow extends StatelessWidget {
  const ParticipantRow({
    super.key,
    required this.user,
    required this.role,
    required this.currentUserID,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final User user;
  final CollectionParticipantRole role;
  final int currentUserID;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return ShareMenuItem(
      title: user.id == currentUserID
          ? context.strings.you
          : resolveDisplayName(user),
      titleMaxLines: 1,
      subtitle: shareableRoleLabel(context, role),
      subtitleMaxLines: 1,
      leading: UserAvatarWidget(user, type: AvatarType.medium),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
