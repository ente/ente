import "dart:async";

import "package:ente_components/ente_components.dart";
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

                  return ButtonComponent(
                    label: AppLocalizations.of(context).save,
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
      body: AppBarComponent(
        title: AppLocalizations.of(context).people,
        subtitle: hasInstalledAny
            ? AppLocalizations.of(context).peopleWidgetDesc
            : context.l10n.addPeopleWidgetPrompt,
        slivers: <Widget>[
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
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: MenuComponent(
                    title: AppLocalizations.of(context).showTextOnWidget,
                    trailing: ToggleSwitchComponent(
                      selected: _showText,
                      onChanged: (showText) async {
                        setState(() => _showText = showText);
                        await localSettings.setWidgetTextHidden(
                          WidgetHideTextFlag.people,
                          !showText,
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
