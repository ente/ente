import "dart:async";

import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/home_widget_service.dart";
import "package:photos/services/people_home_widget_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import 'package:photos/ui/components/buttons/icon_button_widget.dart';
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/models/button_type.dart";
import 'package:photos/ui/components/title_bar_title_widget.dart';
import 'package:photos/ui/components/title_bar_widget.dart';
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/viewer/search/result/people_section_all_page.dart";

class PeopleWidgetSettings extends StatefulWidget {
  const PeopleWidgetSettings({super.key});

  @override
  State<PeopleWidgetSettings> createState() => _PeopleWidgetSettingsState();
}

class _PeopleWidgetSettingsState extends State<PeopleWidgetSettings> {
  bool hasInstalledAny = false;
  late bool _showText;
  final _selectedPeople = SelectedPeople();
  Set<String>? lastSelectedPeople;

  @override
  void initState() {
    super.initState();
    _showText = !localSettings.isWidgetTextHidden(WidgetHideTextFlag.people);
    getSelections();
    checkIfAnyWidgetInstalled();
  }

  Future<void> getSelections() async {
    final selectedPeople = PeopleHomeWidgetService.instance.getSelectedPeople();

    if (selectedPeople != null) {
      _selectedPeople.select(selectedPeople.toSet());
      lastSelectedPeople = selectedPeople.toSet();
    }
  }

  Future<void> checkIfAnyWidgetInstalled() async {
    final count = await PeopleHomeWidgetService.instance.countHomeWidgets();
    setState(() => hasInstalledAny = count > 0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      bottomNavigationBar: hasInstalledAny
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                8 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: ListenableBuilder(
                listenable: _selectedPeople,
                builder: (context, _) {
                  final areIdsChanged = lastSelectedPeople != null
                      ? !setEquals(
                          _selectedPeople.personIds,
                          lastSelectedPeople,
                        )
                      : _selectedPeople.personIds.isNotEmpty;

                  return ButtonWidget(
                    buttonType: ButtonType.primary,
                    buttonSize: ButtonSize.large,
                    labelText: AppLocalizations.of(context).save,
                    shouldSurfaceExecutionStates: false,
                    isDisabled: !areIdsChanged,
                    onTap: areIdsChanged
                        ? () async {
                            unawaited(
                              PeopleHomeWidgetService.instance
                                  .setSelectedPeople(
                                    _selectedPeople.personIds.toList(),
                                  ),
                            );
                            Navigator.pop(context);
                          }
                        : null,
                  );
                },
              ),
            )
          : null,
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          TitleBarWidget(
            backgroundColor: colorScheme.backgroundColour,
            flexibleSpaceTitle: TitleBarTitleWidget(
              title: AppLocalizations.of(context).people,
            ),
            expandedHeight: MediaQuery.textScalerOf(context).scale(136),
            flexibleSpaceCaption: hasInstalledAny
                ? AppLocalizations.of(context).peopleWidgetDesc
                : context.l10n.addPeopleWidgetPrompt,
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
                    Image.asset("assets/people-widget-static.png", height: 160),
                  ],
                ),
              ),
            )
          else ...[
            if (kDebugMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
                  child: MenuItemWidgetNew(
                    title: AppLocalizations.of(context).showTextOnWidget,
                    trailingWidget: ToggleSwitchWidget(
                      value: () => _showText,
                      onChanged: () async {
                        final next = !_showText;
                        setState(() => _showText = next);
                        await localSettings.setWidgetTextHidden(
                          WidgetHideTextFlag.people,
                          !next,
                        );
                        await HomeWidgetService.instance.updateWidget(
                          androidClass:
                              PeopleHomeWidgetService.ANDROID_CLASS_NAME,
                          iOSClass: PeopleHomeWidgetService.IOS_CLASS_NAME,
                        );
                      },
                    ),
                  ),
                ),
              ),
            SliverFillRemaining(
              child: PeopleSectionAllWidget(
                selectedPeople: _selectedPeople,
                namedOnly: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
