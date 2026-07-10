import 'package:flutter/material.dart';
import "package:intl/intl.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/core/constants.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/service_locator.dart";
import "package:photos/states/location_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/bottom_of_title_bar_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/divider_widget.dart";
import 'package:photos/ui/components/keyboard/keyboard_oveylay.dart';
import "package:photos/ui/components/keyboard/keyboard_top_button.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/text_input_widget.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import 'package:photos/ui/viewer/location/dynamic_location_gallery_widget.dart';
import "package:photos/ui/viewer/location/edit_center_point_tile_widget.dart";
import "package:photos/ui/viewer/location/radius_picker_widget.dart";

void showEditLocationSheet(
  BuildContext context,
  LocalEntity<LocationTag> locationTagEntity,
) {
  showBarModalBottomSheet(
    context: context,
    builder: (context) {
      return LocationTagStateProvider(
        locationTagEntity: locationTagEntity,
        const EditLocationSheet(),
      );
    },
    shape: const RoundedRectangleBorder(
      side: BorderSide(width: 0),
      borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
    ),
    topControl: const SizedBox.shrink(),
    backgroundColor: getEnteColorScheme(context).backgroundElevated,
    barrierColor: backdropFaintDark,
  );
}

class EditLocationSheet extends StatefulWidget {
  const EditLocationSheet({super.key});

  @override
  State<EditLocationSheet> createState() => _EditLocationSheetState();
}

class _EditLocationSheetState extends State<EditLocationSheet> {
  //The value of these notifiers has no significance.
  //When memoriesCountNotifier is null, we show the loading widget in the
  //memories count section which also means the gallery is loading.
  final ValueNotifier<int?> _memoriesCountNotifier = ValueNotifier(null);
  final ValueNotifier<bool> _submitNotifer = ValueNotifier(false);
  final ValueNotifier<bool> _cancelNotifier = ValueNotifier(false);
  final ValueNotifier<double> _selectedRadiusNotifier = ValueNotifier(
    defaultRadiusValue,
  );
  final _focusNode = FocusNode();
  final _textEditingController = TextEditingController();
  final _isEmptyNotifier = ValueNotifier(false);
  Widget? _keyboardTopButtons;

  @override
  void initState() {
    _focusNode.addListener(_focusNodeListener);
    _selectedRadiusNotifier.addListener(_selectedRadiusListener);
    super.initState();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusNodeListener);
    _submitNotifer.dispose();
    _cancelNotifier.dispose();
    _selectedRadiusNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final locationName = InheritedLocationTagData.of(
      context,
    ).locationTagEntity!.item.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: BottomOfTitleBarWidget(
              title: TitleBarTitleWidget(
                title: AppLocalizations.of(context).editLocationTagTitle,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                decelerationRate: ScrollDecelerationRate.fast,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextInputWidget(
                                hintText: AppLocalizations.of(
                                  context,
                                ).locationName,
                                focusNode: _focusNode,
                                submitNotifier: _submitNotifer,
                                cancelNotifier: _cancelNotifier,
                                popNavAfterSubmission: false,
                                shouldUnfocusOnClearOrSubmit: true,
                                alwaysShowSuccessState: true,
                                initialValue: locationName,
                                onCancel: () {
                                  _focusNode.unfocus();
                                  _textEditingController.value =
                                      TextEditingValue(text: locationName);
                                },
                                textEditingController: _textEditingController,
                                isEmptyNotifier: _isEmptyNotifier,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ValueListenableBuilder(
                              valueListenable: _isEmptyNotifier,
                              builder: (context, bool value, _) {
                                return AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  switchInCurve: Curves.easeInOut,
                                  switchOutCurve: Curves.easeInOut,
                                  child: ButtonWidget(
                                    key: ValueKey(value),
                                    buttonType: ButtonType.secondary,
                                    buttonSize: ButtonSize.small,
                                    labelText: AppLocalizations.of(
                                      context,
                                    ).save,
                                    isDisabled: value,
                                    onTap: () async {
                                      _focusNode.unfocus();
                                      await _editLocation();
                                    },
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const EditCenterPointTileWidget(),
                        const SizedBox(height: 20),
                        RadiusPickerWidget(_selectedRadiusNotifier),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  const DividerWidget(
                    dividerType: DividerType.solid,
                    padding: EdgeInsets.only(top: 24, bottom: 20),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ValueListenableBuilder(
                        valueListenable: _memoriesCountNotifier,
                        builder: (context, int? value, _) {
                          Widget widget;
                          if (value == null) {
                            widget = EnteLoadingWidget(
                              size: 14,
                              color: colorScheme.strokeMuted,
                              alignment: Alignment.centerLeft,
                              padding: 3,
                            );
                          } else {
                            widget = Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppLocalizations.of(context).memoryCount(
                                    count: value,
                                    formattedCount: NumberFormat().format(
                                      value,
                                    ),
                                  ),
                                  style: textTheme.body,
                                ),
                                if (value > 1000)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).galleryMemoryLimitInfo,
                                      style: textTheme.miniMuted,
                                    ),
                                  ),
                              ],
                            );
                          }
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              switchInCurve: Curves.easeInOutExpo,
                              switchOutCurve: Curves.easeInOutExpo,
                              child: widget,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  DynamicLocationGalleryWidget(
                    _memoriesCountNotifier,
                    "Edit_location",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLocation() async {
    final locationTagState = InheritedLocationTagData.of(context);
    await locationService.updateLocationTag(
      locationTagEntity: locationTagState.locationTagEntity!,
      newRadius: locationTagState.selectedRadius,
      newName: _textEditingController.text.trim(),
      newCenterPoint: InheritedLocationTagData.of(context).centerPoint,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _focusNodeListener() {
    final bool hasFocus = _focusNode.hasFocus;
    _keyboardTopButtons ??= KeyboardTopButton(
      onDoneTap: () {
        _submitNotifer.value = !_submitNotifer.value;
      },
      onCancelTap: () {
        _cancelNotifier.value = !_cancelNotifier.value;
      },
    );
    if (hasFocus) {
      KeyboardOverlay.showOverlay(context, _keyboardTopButtons!);
    } else {
      KeyboardOverlay.removeOverlay();
    }
  }

  void _selectedRadiusListener() {
    InheritedLocationTagData.of(
      context,
    ).updateSelectedRadius(_selectedRadiusNotifier.value);
    _memoriesCountNotifier.value = null;
  }
}
