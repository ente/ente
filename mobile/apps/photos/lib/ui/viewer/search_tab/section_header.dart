import "package:ente_components/theme/text_styles.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/viewer/search/result/people_section_all_page.dart";
import "package:photos/ui/viewer/search/result/search_section_all_page.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";

class SectionHeader extends StatelessWidget {
  final SectionType sectionType;
  final bool hasMore;
  final bool showSearch;
  const SectionHeader(
    this.sectionType, {
    required this.hasMore,
    this.showSearch = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: searchTabSectionHorizontalPadding,
      ),
      child: GestureDetector(
        onTap: () {
          if (hasMore) {
            routeToPage(context, _sectionAllPage());
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  sectionType.sectionTitle(context),
                  style: TextStyles.display3.copyWith(
                    color: colorScheme.textBase,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              hasMore
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showSearch)
                          IconButtonWidget(
                            icon: Icons.search,
                            iconButtonType: IconButtonType.secondary,
                            iconColor: colorScheme.blurStrokePressed,
                            onTap: () {
                              routeToPage(
                                context,
                                _sectionAllPage(startInSearchMode: true),
                              );
                            },
                          ),
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.chevron_right_outlined,
                            color: colorScheme.blurStrokePressed,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionAllPage({bool startInSearchMode = false}) {
    if (sectionType == SectionType.face) {
      return PeopleSectionAllPage(startInSearchMode: startInSearchMode);
    }
    return SearchSectionAllPage(
      sectionType: sectionType,
      startInSearchMode: startInSearchMode,
    );
  }
}
