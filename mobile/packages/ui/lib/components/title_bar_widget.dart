import 'package:ente_ui/components/buttons/icon_button_widget.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class TitleBarWidget extends StatelessWidget {
  final IconButtonWidget? leading;
  final String? title;
  final String? caption;
  final Widget? flexibleSpaceTitle;
  final String? flexibleSpaceCaption;
  final List<Widget>? actionIcons;
  final bool isTitleH2WithoutLeading;
  final bool isFlexibleSpaceDisabled;
  final bool isOnTopOfScreen;
  final Color? backgroundColor;
  const TitleBarWidget({
    super.key,
    this.leading,
    this.title,
    this.caption,
    this.flexibleSpaceTitle,
    this.flexibleSpaceCaption,
    this.actionIcons,
    this.isTitleH2WithoutLeading = false,
    this.isFlexibleSpaceDisabled = false,
    this.isOnTopOfScreen = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    const toolbarHeight = 48.0;
    final textTheme = getEnteTextTheme(context);
    final colorTheme = getEnteColorScheme(context);
    return SliverAppBar(
      backgroundColor: backgroundColor,
      primary: isOnTopOfScreen ? true : false,
      toolbarHeight: toolbarHeight,
      leadingWidth: 48,
      automaticallyImplyLeading: false,
      pinned: true,
      expandedHeight: isFlexibleSpaceDisabled ? toolbarHeight : 102,
      centerTitle: false,
      titleSpacing: 4,
      title: Padding(
        padding: EdgeInsets.only(left: isTitleH2WithoutLeading ? 16 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            title == null
                ? const SizedBox.shrink()
                : Text(
                    title!,
                    style: isTitleH2WithoutLeading
                        ? textTheme.h2Bold
                        : textTheme.largeBold,
                  ),
            caption == null || isTitleH2WithoutLeading
                ? const SizedBox.shrink()
                : Text(
                    caption!,
                    style: textTheme.mini.copyWith(color: colorTheme.textMuted),
                  ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: _actionsWithPaddingInBetween()),
        ),
      ],
      leading: isTitleH2WithoutLeading
          ? null
          : leading ??
                IconButtonWidget(
                  icon: Icons.arrow_back_outlined,
                  iconButtonType: IconButtonType.primary,
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
      flexibleSpace: isFlexibleSpaceDisabled
          ? null
          : FlexibleSpaceBar(
              background: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: toolbarHeight),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          flexibleSpaceTitle == null
                              ? const SizedBox.shrink()
                              : flexibleSpaceTitle!,
                          flexibleSpaceCaption == null
                              ? const SizedBox.shrink()
                              : Text(
                                  flexibleSpaceCaption!,
                                  style: textTheme.small.copyWith(
                                    color: colorTheme.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _actionsWithPaddingInBetween() {
    if (actionIcons == null) {
      return <Widget>[const SizedBox.shrink()];
    }
    final actions = <Widget>[];
    bool addWhiteSpace = false;
    final length = actionIcons!.length;
    int index = 0;
    if (length == 0) {
      return <Widget>[const SizedBox.shrink()];
    }
    if (length == 1) {
      return actionIcons!;
    }
    while (index < length) {
      if (!addWhiteSpace) {
        actions.add(actionIcons![index]);
        index++;
        addWhiteSpace = true;
      } else {
        actions.add(const SizedBox(width: 4));
        addWhiteSpace = false;
      }
    }
    return actions;
  }
}
