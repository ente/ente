import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/utils/dialog_util.dart";
import "package:rive/rive.dart" as rive;

Future<bool> showSharingProgressSheet(
  BuildContext context, {
  required Future<bool> Function() task,
}) async {
  Object? taskError;
  final result = await showBottomSheetComponent<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (sheetContext) => _SharingProgressSheet(
      task: () async {
        try {
          return await task();
        } catch (error) {
          taskError = error;
          return false;
        }
      },
    ),
  );
  if (taskError != null && context.mounted) {
    await showGenericErrorDialog(context: context, error: taskError);
  }
  return result ?? false;
}

class _SharingProgressSheet extends StatefulWidget {
  const _SharingProgressSheet({required this.task});

  final Future<bool> Function() task;

  @override
  State<_SharingProgressSheet> createState() => _SharingProgressSheetState();
}

class _SharingProgressSheetState extends State<_SharingProgressSheet> {
  static const _animationAsset = "assets/invite.riv";
  static const _stateMachineName = "State Machine 1";
  static const _successName = "success";

  late final rive.FileLoader _animationLoader;
  rive.ViewModelInstanceTrigger? _successTrigger;
  bool _sharingSucceeded = false;

  @override
  void initState() {
    super.initState();
    _animationLoader = rive.FileLoader.fromAsset(
      _animationAsset,
      riveFactory: rive.Factory.flutter,
    );
    unawaited(_runTask());
  }

  @override
  void dispose() {
    _animationLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      showCloseButton: false,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      padding: const EdgeInsets.fromLTRB(Spacing.xl, 51, Spacing.xl, 44),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 143,
            child: ExcludeSemantics(
              child: rive.RiveWidgetBuilder(
                fileLoader: _animationLoader,
                stateMachineSelector: const rive.StateMachineNamed(
                  _stateMachineName,
                ),
                dataBind: rive.DataBind.auto(),
                onLoaded: _onRiveLoaded,
                builder: (context, state) => state is rive.RiveLoaded
                    ? rive.RiveWidget(
                        controller: state.controller,
                        fit: rive.Fit.contain,
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(
            context.strings.sharing,
            textAlign: TextAlign.center,
            style: TextStyles.display2.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runTask() async {
    final succeeded = await widget.task();
    if (!mounted) {
      return;
    }
    if (!succeeded) {
      Navigator.of(context).pop(false);
      return;
    }
    _sharingSucceeded = true;
    _successTrigger?.trigger();
  }

  void _onRiveLoaded(rive.RiveLoaded state) {
    state.controller.stateMachine.addEventListener(_onRiveEvent);
    _successTrigger = state.viewModelInstance?.trigger(_successName);
    if (_sharingSucceeded) {
      _successTrigger?.trigger();
    }
  }

  Future<void> _onRiveEvent(rive.Event event) async {
    if (event.name == _successName) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    }
  }
}
