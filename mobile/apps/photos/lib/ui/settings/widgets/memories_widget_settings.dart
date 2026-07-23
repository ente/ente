import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/home_widget_service.dart";
import "package:photos/services/memory_home_widget_service.dart";
import "package:photos/settings/local_settings.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/buttons/icon_button_widget.dart';
import "package:photos/ui/components/captioned_text_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import 'package:photos/ui/components/title_bar_title_widget.dart';
import 'package:photos/ui/components/title_bar_widget.dart';
import "package:photos/ui/components/toggle_switch_widget.dart";

class MemoriesWidgetSettings extends StatefulWidget {
  const MemoriesWidgetSettings({super.key});

  @override
  State<MemoriesWidgetSettings> createState() => _MemoriesWidgetSettingsState();
}

class _MemoriesWidgetSettingsState extends State<MemoriesWidgetSettings> {
  bool hasInstalledAny = false;

  bool? isYearlyMemoriesEnabled = true;
  bool? isSmartMemoriesEnabled = false;
  bool? isOnThisDayMemoriesEnabled = false;
  late bool _showText;

  late final bool isMLEnabled;

  late Debouncer _changeMemoriesSettings;

  @override
  void initState() {
    super.initState();

    _showText = !localSettings.isWidgetTextHidden(WidgetHideTextFlag.memory);
    initVariables();
    checkIfAnyWidgetInstalled();
  }

  Future<void> checkIfAnyWidgetInstalled() async {
    final count = await MemoryHomeWidgetService.instance.countHomeWidgets();
    setState(() {
      hasInstalledAny = count > 0;
    });
  }

  Future<void> initVariables() async {
    _changeMemoriesSettings = Debouncer(const Duration(milliseconds: 2500));
    isMLEnabled = hasGrantedMLConsent;
    isYearlyMemoriesEnabled = MemoryHomeWidgetService.instance
        .hasLastYearMemoriesSelected();
    isSmartMemoriesEnabled = MemoryHomeWidgetService.instance
        .getMLMemoriesSelected();
    isOnThisDayMemoriesEnabled = MemoryHomeWidgetService.instance
        .getOnThisDayMemoriesSelected();

    if (isYearlyMemoriesEnabled == null ||
        isSmartMemoriesEnabled == null ||
        isOnThisDayMemoriesEnabled == null) {
      if (isMLEnabled) {
        enableMLMemories();
      } else {
        enableNonMLMemories();
      }
    }

    setState(() {});
  }

  void enableMLMemories() {
    isYearlyMemoriesEnabled = false;
    isSmartMemoriesEnabled = true;
    isOnThisDayMemoriesEnabled = false;
  }

  void enableNonMLMemories() {
    isYearlyMemoriesEnabled = true;
    isSmartMemoriesEnabled = false;
    isOnThisDayMemoriesEnabled = true;
  }

  Future<void> updateVariables() async {
    _changeMemoriesSettings.run(MemoryHomeWidgetService.instance.memoryChanged);
    await MemoryHomeWidgetService.instance.setLastYearMemoriesSelected(
      isYearlyMemoriesEnabled!,
    );
    await MemoryHomeWidgetService.instance.setSelectedMLMemories(
      isSmartMemoriesEnabled!,
    );
    await MemoryHomeWidgetService.instance.setOnThisDayMemoriesSelected(
      isOnThisDayMemoriesEnabled!,
    );
    await MemoryHomeWidgetService.instance.memoryChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            backgroundColor: colorScheme.backgroundColour,
            flexibleSpaceTitle: TitleBarTitleWidget(
              title: AppLocalizations.of(context).memories,
            ),
            expandedHeight: MediaQuery.textScalerOf(context).scale(136),
            flexibleSpaceCaption: hasInstalledAny
                ? AppLocalizations.of(context).memoriesWidgetDesc
                : context.l10n.addMemoriesWidgetPrompt,
            actionIcons: [
              IconButtonWidget(
                icon: Icons.close_outlined,
                iconButtonType: IconButtonType.secondary,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          if (!hasInstalledAny)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.5 - 200,
                    ),
                    Image.asset(
                      "assets/memories-widget-static.png",
                      height: 160,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 18),
                      if (kDebugMode) ...[
                        MenuItemWidgetNew(
                          title: AppLocalizations.of(context).showTextOnWidget,
                          trailingWidget: ToggleSwitchWidget(
                            value: () => _showText,
                            onChanged: () async {
                              final next = !_showText;
                              setState(() => _showText = next);
                              await localSettings.setWidgetTextHidden(
                                WidgetHideTextFlag.memory,
                                !next,
                              );
                              await HomeWidgetService.instance.updateWidget(
                                androidClass:
                                    MemoryHomeWidgetService.ANDROID_CLASS_NAME,
                                iOSClass:
                                    MemoryHomeWidgetService.IOS_CLASS_NAME,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      MenuItemWidget(
                        captionedTextWidget: CaptionedTextWidget(
                          title: AppLocalizations.of(context).pastYearsMemories,
                        ),
                        leadingIconWidget: SvgPicture.asset(
                          "assets/icons/past-year-memory-icon.svg",
                          colorFilter: ColorFilter.mode(
                            colorScheme.textBase,
                            BlendMode.srcIn,
                          ),
                        ),
                        menuItemColor: colorScheme.fillFaint,
                        trailingWidget: ToggleSwitchWidget(
                          value: () => isYearlyMemoriesEnabled ?? true,
                          onChanged: () async {
                            setState(() {
                              isYearlyMemoriesEnabled =
                                  !isYearlyMemoriesEnabled!;
                            });
                            updateVariables().ignore();
                          },
                        ),
                        singleBorderRadius: 8,
                        isGestureDetectorDisabled: true,
                      ),
                      const SizedBox(height: 4),
                      MenuItemWidget(
                        captionedTextWidget: CaptionedTextWidget(
                          title: AppLocalizations.of(context).onThisDayMemories,
                        ),
                        leadingIconWidget: SvgPicture.asset(
                          "assets/icons/memories-widget-icon.svg",
                          colorFilter: ColorFilter.mode(
                            colorScheme.textBase,
                            BlendMode.srcIn,
                          ),
                        ),
                        menuItemColor: colorScheme.fillFaint,
                        trailingWidget: ToggleSwitchWidget(
                          value: () => isOnThisDayMemoriesEnabled!,
                          onChanged: () async {
                            setState(() {
                              isOnThisDayMemoriesEnabled =
                                  !isOnThisDayMemoriesEnabled!;
                            });
                            updateVariables().ignore();
                          },
                        ),
                        singleBorderRadius: 8,
                        isGestureDetectorDisabled: true,
                      ),
                      if (isMLEnabled) ...[
                        const SizedBox(height: 4),
                        MenuItemWidget(
                          captionedTextWidget: CaptionedTextWidget(
                            title: AppLocalizations.of(context).smartMemories,
                          ),
                          leadingIconWidget: SvgPicture.asset(
                            "assets/icons/smart-memory-icon.svg",
                            colorFilter: ColorFilter.mode(
                              colorScheme.textBase,
                              BlendMode.srcIn,
                            ),
                          ),
                          menuItemColor: colorScheme.fillFaint,
                          trailingWidget: ToggleSwitchWidget(
                            value: () => isSmartMemoriesEnabled!,
                            onChanged: () async {
                              setState(() {
                                isSmartMemoriesEnabled =
                                    !isSmartMemoriesEnabled!;
                              });

                              updateVariables().ignore();
                            },
                          ),
                          singleBorderRadius: 8,
                          isGestureDetectorDisabled: true,
                        ),
                      ],
                    ],
                  ),
                );
              }, childCount: 1),
            ),
        ],
      ),
    );
  }
}
