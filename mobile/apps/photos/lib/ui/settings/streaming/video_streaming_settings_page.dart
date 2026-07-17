import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/video_preview_state_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

const helpUrl =
    "https://ente.com/help/photos/features/utilities/video-streaming#related-faqs";

class VideoStreamingSettingsPage extends StatefulWidget {
  const VideoStreamingSettingsPage({super.key});

  @override
  State<VideoStreamingSettingsPage> createState() =>
      _VideoStreamingSettingsPageState();
}

class _VideoStreamingSettingsPageState
    extends State<VideoStreamingSettingsPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasEnabled = VideoPreviewService.instance.isVideoStreamingEnabled;
    final children = hasEnabled
        ? _enabledChildren(context)
        : _disabledChildren(context);

    return SettingsPageScaffold(
      title: l10n.videoStreaming,
      bottomNavigationBar: !hasEnabled
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                ).copyWith(bottom: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    ButtonComponent(
                      label: context.l10n.enable,
                      onTap: () async {
                        await toggleVideoStreaming();
                      },
                    ),
                  ],
                ),
              ),
            )
          : null,
      children: children,
    );
  }

  List<Widget> _enabledChildren(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    return [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: l10n.videoStreamingDescriptionLine1),
            const TextSpan(text: " "),
            TextSpan(text: l10n.videoStreamingDescriptionLine2),
            const TextSpan(text: "\n"),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: openHelp,
                child: Text(
                  l10n.moreDetails,
                  style: TextStyles.bodyLink.copyWith(
                    color: colors.primary,
                    decorationColor: colors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
        style: TextStyles.body.copyWith(color: colors.textLight),
      ),
      const SizedBox(height: 24),
      MenuComponent(
        title: l10n.enabled,
        leading: _streamingMenuIcon(context, HugeIcons.strokeRoundedToggleOn),
        trailing: ToggleSwitchComponent.async(
          value: () => VideoPreviewService.instance.isVideoStreamingEnabled,
          onChanged: () async {
            await toggleVideoStreaming();
          },
        ),
      ),
      const SizedBox(height: 8),
      const VideoStreamingStatusWidget(),
    ];
  }

  List<Widget> _disabledChildren(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    return [
      const SizedBox(height: 80),
      Image.asset("assets/enable-streaming-static.png", height: 160),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: l10n.videoStreamingDescriptionLine1),
              const TextSpan(text: "\n"),
              TextSpan(text: l10n.videoStreamingDescriptionLine2),
              const TextSpan(text: "\n"),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: openHelp,
                  child: Text(
                    l10n.moreDetails,
                    style: TextStyles.bodyLink.copyWith(
                      color: colors.primary,
                      decorationColor: colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          style: TextStyles.body.copyWith(color: colors.textLight),
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 140),
    ];
  }

  Future<void> openHelp() async {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return WebPage(AppLocalizations.of(context).help, helpUrl);
            },
          ),
        )
        .ignore();
  }

  Future<void> toggleVideoStreaming() async {
    final isEnabled = VideoPreviewService.instance.isVideoStreamingEnabled;

    await VideoPreviewService.instance.setIsVideoStreamingEnabled(!isEnabled);
    if (!mounted) return;
    setState(() {});
  }
}

class VideoStreamingStatusWidget extends StatefulWidget {
  const VideoStreamingStatusWidget({super.key});

  @override
  State<VideoStreamingStatusWidget> createState() =>
      VideoStreamingStatusWidgetState();
}

class VideoStreamingStatusWidgetState
    extends State<VideoStreamingStatusWidget> {
  double? _netProcessed;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    init();
    _subscription = Bus.instance.on<VideoPreviewStateChangedEvent>().listen((
      event,
    ) {
      final status = event.status;

      // Handle different states
      switch (status) {
        case PreviewItemStatus.uploaded:
          init();
          break;
        default:
      }
    });
  }

  Future<void> init() async {
    _netProcessed = await VideoPreviewService.instance.getStatus();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      children: [
        if (_netProcessed != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MenuComponent(
                title: AppLocalizations.of(context).processed,
                leading: _streamingMenuIcon(
                  context,
                  HugeIcons.strokeRoundedClock01,
                ),
                trailing: Text(
                  _netProcessed == 0
                      ? '0%'
                      : '${(_netProcessed! * 100.0).toStringAsFixed(2)}%',
                  style: TextStyles.mini.copyWith(color: colors.textLight),
                ),
                key: ValueKey("processed_items_$_netProcessed"),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppLocalizations.of(context).videoStreamingNote,
                  style: TextStyles.body.copyWith(color: colors.textLight),
                ),
              ),
            ],
          )
        else
          const EnteLoadingWidget(),
      ],
    );
  }
}

Widget _streamingMenuIcon(BuildContext context, List<List<dynamic>> icon) {
  return HugeIcon(
    icon: icon,
    color: context.componentColors.textLight,
    size: IconSizes.small,
    strokeWidth: 1.6,
  );
}
