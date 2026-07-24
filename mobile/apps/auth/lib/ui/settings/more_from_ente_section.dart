import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MoreFromEnteSection extends StatelessWidget {
  const MoreFromEnteSection({
    super.key,
    required this.currentApp,
    required this.moreFromLabel,
    required this.onAppTap,
  });

  final ComponentApp currentApp;
  final String moreFromLabel;
  final ValueChanged<ComponentApp> onAppTap;

  @override
  Widget build(BuildContext context) {
    final apps = _otherApps[currentApp]!;

    return SizedBox(
      key: const ValueKey('more-from-ente'),
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MoreFromEnteBrand(label: moreFromLabel),
          const SizedBox(height: _sectionGap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnteAppLink(app: apps.first, onTap: onAppTap),
              const SizedBox(width: _appGap),
              _EnteAppLink(app: apps.last, onTap: onAppTap),
            ],
          ),
        ],
      ),
    );
  }
}

Uri moreFromEnteUri({
  required ComponentApp sourceApp,
  required ComponentApp destinationApp,
}) {
  final path = switch (destinationApp) {
    ComponentApp.photos => '/',
    ComponentApp.locker => '/locker',
    ComponentApp.auth => '/auth',
  };
  return Uri.https('ente.com', path, {'from': sourceApp.name});
}

class _MoreFromEnteBrand extends StatelessWidget {
  const _MoreFromEnteBrand({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return SizedBox(
      key: const ValueKey('more-from-ente-brand'),
      width: _brandWidth,
      height: _brandHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: _moreFromLineHeight,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: colors.primary,
                fontFamily: 'Gochi Hand',
                fontFamilyFallback: const [TextStyles.fontFamily],
                fontSize: 26.279,
                height: 1.02,
                letterSpacing: -1.0512,
              ),
            ),
          ),
          SvgPicture.asset(
            'assets/svg/ente_wordmark.svg',
            width: _wordmarkWidth,
            height: _wordmarkHeight,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(colors.textBase, BlendMode.srcIn),
          ),
        ],
      ),
    );
  }
}

class _EnteAppLink extends StatelessWidget {
  const _EnteAppLink({required this.app, required this.onTap});

  final ComponentApp app;
  final ValueChanged<ComponentApp> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final label = _appLabels[app]!;

    return Semantics(
      button: true,
      label: 'Ente $label',
      child: SizedBox(
        width: _appTileSize,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Material(
                  key: ValueKey('more-from-ente-${app.name}'),
                  type: MaterialType.transparency,
                  borderRadius: BorderRadius.circular(_appRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onTap(app),
                    child: const SizedBox.square(dimension: _appTileSize),
                  ),
                ),
                IgnorePointer(
                  child: EnteAppIcon(app: app, size: _appIconSize),
                ),
              ],
            ),
            const SizedBox(height: _appLabelGap),
            SizedBox(
              height: _appLabelHeight,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _otherApps = <ComponentApp, List<ComponentApp>>{
  ComponentApp.photos: [ComponentApp.locker, ComponentApp.auth],
  ComponentApp.auth: [ComponentApp.photos, ComponentApp.locker],
  ComponentApp.locker: [ComponentApp.photos, ComponentApp.auth],
};

const _appLabels = <ComponentApp, String>{
  ComponentApp.photos: 'Photos',
  ComponentApp.auth: 'Auth',
  ComponentApp.locker: 'Locker',
};

const double _brandWidth = 103;
const double _brandHeight = 45.43;
const double _moreFromLineHeight = 27;
const double _wordmarkWidth = 62;
const double _wordmarkHeight = 18.43;
const double _sectionGap = 16;
const double _appTileSize = 52;
const double _appIconSize = 31;
const double _appRadius = 16.774;
const double _appLabelGap = 8;
const double _appLabelHeight = 16;
const double _appGap = 39;
