import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/buttons/icon_button_widget.dart';

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
  final bool isSliver;
  final double? expandedHeight;
  final double reducedExpandedHeight;

  const TitleBarWidget({
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
    this.isSliver = true,
    this.expandedHeight,
    this.reducedExpandedHeight = 0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const toolbarHeight = 48.0;
    if (isSliver) {
      return SliverAppBar(
        backgroundColor: backgroundColor,
        primary: isOnTopOfScreen ? true : false,
        toolbarHeight: toolbarHeight,
        leadingWidth: 48,
        automaticallyImplyLeading: false,
        pinned: true,
        expandedHeight:
            expandedHeight ??
            (isFlexibleSpaceDisabled ? toolbarHeight : 102) -
                reducedExpandedHeight,
        centerTitle: false,
        titleSpacing: 4,
        title: TitleWidget(
          title: title,
          caption: caption,
          isTitleH2WithoutLeading: isTitleH2WithoutLeading,
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
                    icon: Icons.adaptive.arrow_back_outlined,
                    iconButtonType: IconButtonType.primary,
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
        flexibleSpace: isFlexibleSpaceDisabled
            ? null
            : FlexibleSpaceBarWidget(
                flexibleSpaceTitle,
                flexibleSpaceCaption,
                toolbarHeight,
                maxLines: expandedHeight == null ? 1 : 2,
              ),
      );
    } else {
      return AppBar(
        backgroundColor: backgroundColor,
        primary: isOnTopOfScreen ? true : false,
        toolbarHeight: toolbarHeight,
        leadingWidth: 48,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 4,
        title: TitleWidget(
          title: title,
          caption: caption,
          isTitleH2WithoutLeading: isTitleH2WithoutLeading,
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
                    icon: Icons.adaptive.arrow_back_outlined,
                    iconButtonType: IconButtonType.primary,
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
        flexibleSpace: isFlexibleSpaceDisabled
            ? null
            : FlexibleSpaceBarWidget(
                flexibleSpaceTitle,
                flexibleSpaceCaption,
                toolbarHeight,
                maxLines: expandedHeight == null ? 1 : 2,
              ),
      );
    }
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

class TitleWidget extends StatelessWidget {
  final String? title;
  final String? caption;
  final bool isTitleH2WithoutLeading;
  const TitleWidget({
    this.title,
    this.caption,
    required this.isTitleH2WithoutLeading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return Padding(
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
              : Text(caption!, style: textTheme.miniMuted),
        ],
      ),
    );
  }
}

class FlexibleSpaceBarWidget extends StatelessWidget {
  final Widget? flexibleSpaceTitle;
  final String? flexibleSpaceCaption;
  final double toolbarHeight;
  final int maxLines;

  const FlexibleSpaceBarWidget(
    this.flexibleSpaceTitle,
    this.flexibleSpaceCaption,
    this.toolbarHeight, {
    super.key,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return FlexibleSpaceBar(
      background: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(height: toolbarHeight),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
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
                          style: textTheme.smallMuted,
                          overflow: TextOverflow.ellipsis,
                          maxLines: maxLines,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
