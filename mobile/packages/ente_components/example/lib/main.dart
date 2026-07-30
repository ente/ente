import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

typedef HugeIconData = List<List<dynamic>>;

void main() {
  runApp(const ComponentsCatalogApp());
}

class ComponentsCatalogApp extends StatefulWidget {
  const ComponentsCatalogApp({super.key});

  @override
  State<ComponentsCatalogApp> createState() => _ComponentsCatalogAppState();
}

class _ComponentsCatalogAppState extends State<ComponentsCatalogApp> {
  ThemeMode _themeMode = ThemeMode.light;
  ComponentApp _appTheme = ComponentApp.photos;
  Duration? _lastPointerUpAt;
  Offset? _lastPointerUpPosition;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePointerEvent,
    );
    super.dispose();
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is! PointerUpEvent) {
      return;
    }

    final now = event.timeStamp;
    final lastPointerUpAt = _lastPointerUpAt;
    final lastPointerUpPosition = _lastPointerUpPosition;
    final isDoubleTap =
        lastPointerUpAt != null &&
        lastPointerUpPosition != null &&
        now - lastPointerUpAt <= const Duration(milliseconds: 320) &&
        (event.position - lastPointerUpPosition).distance <= 48;

    _lastPointerUpAt = isDoubleTap ? null : now;
    _lastPointerUpPosition = isDoubleTap ? null : event.position;

    if (isDoubleTap) {
      _cycleAppTheme();
    }
  }

  void _cycleAppTheme() {
    final nextTheme = switch (_appTheme) {
      ComponentApp.photos => ComponentApp.locker,
      ComponentApp.locker => ComponentApp.auth,
      ComponentApp.auth => ComponentApp.photos,
    };
    setState(() => _appTheme = nextTheme);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Components',
      theme: ComponentTheme.lightTheme(app: _appTheme),
      darkTheme: ComponentTheme.darkTheme(app: _appTheme),
      themeMode: _themeMode,
      home: CatalogHome(
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }
}

class CatalogHome extends StatefulWidget {
  const CatalogHome({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<CatalogHome> createState() => _CatalogHomeState();
}

class _CatalogHomeState extends State<CatalogHome> {
  late ThemeMode _themeMode = widget.themeMode;

  @override
  void didUpdateWidget(covariant CatalogHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeMode != widget.themeMode) {
      _themeMode = widget.themeMode;
    }
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final sections = _sections();

    return Scaffold(
      drawer: const CatalogSettingsDrawer(),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.backgroundBase,
        foregroundColor: colors.textBase,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Components',
          style: TextStyles.h1Bold.copyWith(color: colors.textBase),
        ),
        leading: Builder(
          builder: (context) {
            return Center(
              child: IconButtonComponent(
                tooltip: 'Settings',
                variant: IconButtonComponentVariant.unfilled,
                onTap: () => Scaffold.of(context).openDrawer(),
                icon: const _CatalogHugeIcon(HugeIcons.strokeRoundedMenu01),
              ),
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Spacing.lg),
            child: _CatalogThemeCycleButton(
              themeMode: _themeMode,
              onChanged: _setThemeMode,
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
        ),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: Spacing.lg),
        itemBuilder: (context, index) {
          return _CatalogSectionTile(
            section: sections[index],
            themeMode: _themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          );
        },
      ),
      backgroundColor: colors.backgroundBase,
    );
  }

  List<CatalogSection> _sections() {
    return [
      CatalogSection(
        title: 'Menu Item',
        icon: HugeIcons.strokeRoundedUser,
        components: const [
          'Default',
          'Selected',
          'Loading',
          'Success',
          'Loading only',
          'Display only',
          'Leading icon',
          'No leading icon',
          'Subtitle',
          'No subtitle',
          'Trailing icon',
          'Trailing toggle',
          'No trailing',
          'Async state',
          'Destructive',
          'Long text',
        ],
        previewBuilder: (_) => const _MenuItemPreview(),
      ),
      CatalogSection(
        title: 'Popup menu',
        icon: HugeIcons.strokeRoundedMoreVertical,
        components: const [
          'Sort menu',
          'Leading icons',
          'Trailing icons',
          'Label icon',
          'Full combo',
          'Active state',
          'All cases',
        ],
        previewBuilder: (_) => const _PopupMenuPreview(),
      ),
      CatalogSection(
        title: 'Banner',
        icon: HugeIcons.strokeRoundedAlertCircle,
        components: const [
          'Failure',
          'Informative',
          'Success',
          'Warning',
          'Neutral',
          'Custom leading',
          'Custom trailing',
        ],
        previewBuilder: (_) => const _BannerPreview(),
      ),
      CatalogSection(
        title: 'Toast',
        icon: HugeIcons.strokeRoundedCheckmarkCircle02,
        components: const [
          'States',
          'Title only',
          'Custom leading',
          'Custom trailing',
          'Short vs long',
        ],
        previewBuilder: (_) => const _ToastPreview(),
      ),
      CatalogSection(
        title: 'Buttons',
        icon: HugeIcons.strokeRoundedCursorPointer02,
        components: const ['Button', 'Icon button'],
        previewBuilder: (_) => const _ButtonMatrix(),
      ),
      CatalogSection(
        title: 'Bottom sheets',
        icon: HugeIcons.strokeRoundedLayoutTable01,
        components: const [
          'Header',
          'Default sheet',
          'Choice sheet',
          'Warning sheet',
          'Error sheet',
          'Custom content',
        ],
        previewBuilder: (_) => const _BottomSheetPreview(),
      ),
      CatalogSection(
        title: 'Text input',
        icon: HugeIcons.strokeRoundedTypeCursor,
        components: const [
          'Single-line states',
          'Multiline states',
          'Label',
          'Trailing icon',
          'Clearable',
          'Password',
          'Warning message',
          'Alert message',
          'Read only',
          'Max length',
        ],
        previewBuilder: (_) => const _TextInputPreview(),
      ),
      CatalogSection(
        title: 'Selection controls',
        icon: HugeIcons.strokeRoundedSlidersHorizontal,
        components: const ['Checkbox', 'Radio', 'Switch', 'Slider', 'Stepper'],
        previewBuilder: (_) => const _SelectionPreview(),
      ),
      CatalogSection(
        title: 'Filter chips',
        icon: HugeIcons.strokeRoundedFilter,
        components: const [
          'Selected',
          'Unselected',
          'Disabled',
          'Leading icon',
          'Trailing icon',
          'Face',
        ],
        previewBuilder: (_) => const _FilterChipPreview(),
      ),
      CatalogSection(
        title: 'Header app bar',
        icon: HugeIcons.strokeRoundedHeading,
        components: const [
          'Expanded header',
          'Collapsed app bar',
          'Scroll animation',
          'Long list',
        ],
        previewBuilder: (_) => const _HeaderAppBarEntryPreview(),
        routeBuilder: _buildHeaderAppBarDemo,
      ),
      CatalogSection(
        title: 'Tooltip',
        icon: HugeIcons.strokeRoundedHelpCircle,
        components: const ['Top pointer', 'Tap trigger'],
        previewBuilder: (_) => const _TooltipPreview(),
      ),
      CatalogSection(
        title: 'Avatar',
        icon: HugeIcons.strokeRoundedUser,
        components: const ['Sizes', 'Seed palette', 'Add contact'],
        previewBuilder: (_) => const _AvatarPreview(),
      ),
      CatalogSection(
        title: 'Text styles',
        icon: HugeIcons.strokeRoundedTextFont,
        components: const ['H1', 'H1-Bold', 'H2', 'Large', 'Body', 'Mini'],
        previewBuilder: (_) => const _TextStylesPreview(),
      ),
    ];
  }
}

typedef CatalogSectionRouteBuilder =
    Widget Function(
      BuildContext context,
      ThemeMode themeMode,
      ValueChanged<ThemeMode> onThemeModeChanged,
    );

Widget _buildHeaderAppBarDemo(
  BuildContext context,
  ThemeMode themeMode,
  ValueChanged<ThemeMode> onThemeModeChanged,
) {
  return HeaderAppBarDemoPage(
    themeMode: themeMode,
    onThemeModeChanged: onThemeModeChanged,
  );
}

class CatalogSection {
  const CatalogSection({
    required this.title,
    required this.icon,
    required this.components,
    required this.previewBuilder,
    this.routeBuilder,
  });

  final String title;
  final HugeIconData icon;
  final List<String> components;
  final WidgetBuilder previewBuilder;
  final CatalogSectionRouteBuilder? routeBuilder;
}

class CatalogSettingsDrawer extends StatelessWidget {
  const CatalogSettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Drawer(
      width: _drawerWidth(context),
      shape: const RoundedRectangleBorder(),
      backgroundColor: colors.backgroundBase,
      child: AppBarComponent(
        title: 'Settings',
        subtitle: 'aman@example.com',
        onBack: () => Navigator.of(context).pop(),
        slivers: const [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              Spacing.sm,
              Spacing.xs,
              Spacing.sm,
              Spacing.lg,
            ),
            sliver: SliverToBoxAdapter(child: _SettingsMainContent()),
          ),
        ],
      ),
    );
  }
}

double _drawerWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width < 430 ? width : 430;
}

class _CatalogHugeIcon extends StatelessWidget {
  const _CatalogHugeIcon(this.icon, {this.color, this.size = IconSizes.medium});

  final HugeIconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return HugeIcon(
      icon: icon,
      color: color ?? IconTheme.of(context).color,
      size: size,
      strokeWidth: 1.6,
    );
  }
}

class _CatalogTrailingIcon extends StatelessWidget {
  const _CatalogTrailingIcon(this.icon);

  final HugeIconData icon;

  @override
  Widget build(BuildContext context) {
    return _CatalogHugeIcon(
      icon,
      color: context.componentColors.textLight,
      size: IconSizes.small,
    );
  }
}

class _CatalogThemeCycleButton extends StatelessWidget {
  const _CatalogThemeCycleButton({
    required this.themeMode,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  ThemeMode get _nextMode {
    return switch (themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.light,
    };
  }

  String get _currentLabel {
    return switch (themeMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Light',
    };
  }

  String get _nextLabel {
    return switch (_nextMode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'Light',
    };
  }

  HugeIconData get _icon {
    return switch (themeMode) {
      ThemeMode.light => HugeIcons.strokeRoundedSun01,
      ThemeMode.dark => HugeIcons.strokeRoundedMoon02,
      ThemeMode.system => HugeIcons.strokeRoundedSun01,
    };
  }

  @override
  Widget build(BuildContext context) {
    return IconButtonComponent(
      tooltip: 'Theme: $_currentLabel. Tap for $_nextLabel',
      variant: IconButtonComponentVariant.primary,
      icon: _CatalogHugeIcon(_icon),
      onTap: () => onChanged(_nextMode),
    );
  }
}

class _CatalogSectionTile extends StatelessWidget {
  const _CatalogSectionTile({
    required this.section,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final CatalogSection section;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MenuComponent(
      key: ValueKey('catalog-section-${section.title}'),
      title: section.title,
      leading: _CatalogHugeIcon(section.icon, size: IconSizes.small),
      trailing: _CatalogHugeIcon(
        HugeIcons.strokeRoundedArrowRight02,
        color: colors.textLight,
        size: IconSizes.small,
      ),
      onTap: () {
        final routeBuilder = section.routeBuilder;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => routeBuilder == null
                ? CatalogDetailPage(
                    section: section,
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                  )
                : routeBuilder(context, themeMode, onThemeModeChanged),
          ),
        );
      },
    );
  }
}

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({
    super.key,
    required this.section,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final CatalogSection section;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  late ThemeMode _themeMode = widget.themeMode;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      body: AppBarComponent(
        title: widget.section.title,
        subtitle: widget.section.components.join(', '),
        onBack: () => Navigator.of(context).pop(),
        actions: [
          _CatalogThemeCycleButton(
            themeMode: _themeMode,
            onChanged: _setThemeMode,
          ),
        ],
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.lg,
            ),
            sliver: SliverToBoxAdapter(
              child: widget.section.previewBuilder(context),
            ),
          ),
        ],
      ),
      backgroundColor: colors.backgroundBase,
    );
  }
}

class _CatalogPreviewGroup extends StatelessWidget {
  const _CatalogPreviewGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyles.large.copyWith(color: colors.textBase)),
        const SizedBox(height: Spacing.md),
        child,
      ],
    );
  }
}

class _CatalogPreviewList extends StatelessWidget {
  const _CatalogPreviewList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) const SizedBox(height: Spacing.xl),
        ],
      ],
    );
  }
}

class _SettingsMainContent extends StatelessWidget {
  const _SettingsMainContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MenuGroupComponent(
          items: [
            _settingsNavigationItem(
              context,
              title: 'Account',
              icon: HugeIcons.strokeRoundedUser,
              page: const _SettingsAccountPage(),
            ),
            _settingsNavigationItem(
              context,
              title: 'Security',
              icon: HugeIcons.strokeRoundedSecurityCheck,
              page: const _SettingsSecurityPage(),
            ),
            _settingsNavigationItem(
              context,
              title: 'Appearance',
              icon: HugeIcons.strokeRoundedPaintBoard,
              page: const _SettingsAppearancePage(),
            ),
          ],
        ),
        const SizedBox(height: Spacing.md),
        _settingsNavigationItem(
          context,
          title: 'General',
          icon: HugeIcons.strokeRoundedSettings01,
          page: const _SettingsGeneralPage(),
        ),
        const SizedBox(height: Spacing.md),
        _settingsNavigationItem(
          context,
          title: 'Help and support',
          icon: HugeIcons.strokeRoundedHelpCircle,
          page: const _SettingsSupportPage(),
        ),
        const SizedBox(height: Spacing.md),
        _settingsNavigationItem(
          context,
          title: 'About',
          icon: HugeIcons.strokeRoundedInformationCircle,
          page: const _SettingsAboutPage(),
        ),
        const SizedBox(height: Spacing.xl),
        MenuComponent(
          title: 'Logout',
          leading: _CatalogHugeIcon(
            HugeIcons.strokeRoundedLogout05,
            color: colors.warning,
          ),
          trailing: _SettingsTrailingIcon(color: colors.textLight),
        ),
        const SizedBox(height: Spacing.xl),
        Center(
          child: Text(
            'Version 1.0.0',
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ),
      ],
    );
  }

  MenuComponent _settingsNavigationItem(
    BuildContext context, {
    required String title,
    required HugeIconData icon,
    required Widget page,
  }) {
    return MenuComponent(
      title: title,
      leading: _CatalogHugeIcon(icon),
      trailing: const _SettingsTrailingIcon(),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => page));
      },
    );
  }
}

class _SettingsTrailingIcon extends StatelessWidget {
  const _SettingsTrailingIcon({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return _CatalogHugeIcon(
      HugeIcons.strokeRoundedArrowRight02,
      color: color ?? context.componentColors.textLight,
      size: IconSizes.small,
    );
  }
}

class _SettingsExampleShell extends StatelessWidget {
  const _SettingsExampleShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      body: AppBarComponent(
        title: title,
        subtitle: 'Settings',
        onBack: () => Navigator.of(context).pop(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.lg,
            ),
            sliver: SliverList.builder(
              itemCount: children.length * 2 - 1,
              itemBuilder: (context, index) {
                if (index.isOdd) {
                  return const SizedBox(height: Spacing.md);
                }
                return children[index ~/ 2];
              },
            ),
          ),
        ],
      ),
      backgroundColor: colors.backgroundBase,
    );
  }
}

class _SettingsAccountPage extends StatelessWidget {
  const _SettingsAccountPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return _SettingsExampleShell(
      title: 'Account',
      children: [
        const MenuComponent(
          title: 'Change email',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedMail01),
          trailing: _SettingsTrailingIcon(),
        ),
        const MenuComponent(
          title: 'Recovery key',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedKey01),
          trailing: _SettingsTrailingIcon(),
        ),
        const MenuComponent(
          title: 'Change password',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedSquareLock02),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Delete account',
          subtitle: 'Demo destructive row',
          leading: _CatalogHugeIcon(
            HugeIcons.strokeRoundedDelete02,
            color: colors.warning,
          ),
          trailing: _SettingsTrailingIcon(color: colors.textLight),
        ),
      ],
    );
  }
}

class _SettingsSecurityPage extends StatefulWidget {
  const _SettingsSecurityPage();

  @override
  State<_SettingsSecurityPage> createState() => _SettingsSecurityPageState();
}

class _SettingsSecurityPageState extends State<_SettingsSecurityPage> {
  bool _emailVerification = true;

  @override
  Widget build(BuildContext context) {
    return _SettingsExampleShell(
      title: 'Security',
      children: [
        MenuComponent(
          title: 'Email verification',
          leading: const _CatalogHugeIcon(HugeIcons.strokeRoundedMailLock02),
          trailing: ToggleSwitchComponent(
            selected: _emailVerification,
            onChanged: (value) {
              setState(() => _emailVerification = value);
            },
          ),
        ),
        const MenuComponent(
          title: 'Passkey',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedFingerPrint),
          trailing: _SettingsTrailingIcon(),
        ),
        const MenuComponent(
          title: 'App lock',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedLockKey),
          trailing: _SettingsTrailingIcon(),
        ),
        const MenuComponent(
          title: 'Active sessions',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedLaptop),
          trailing: _SettingsTrailingIcon(),
        ),
      ],
    );
  }
}

class _SettingsAppearancePage extends StatefulWidget {
  const _SettingsAppearancePage();

  @override
  State<_SettingsAppearancePage> createState() =>
      _SettingsAppearancePageState();
}

class _SettingsAppearancePageState extends State<_SettingsAppearancePage> {
  String _theme = 'System theme';

  @override
  Widget build(BuildContext context) {
    return _SettingsExampleShell(
      title: 'Appearance',
      children: [
        _SettingsThemeOption(
          title: 'System theme',
          icon: HugeIcons.strokeRoundedComputer,
          selected: _theme == 'System theme',
          onTap: () => _selectTheme('System theme'),
        ),
        _SettingsThemeOption(
          title: 'Light theme',
          icon: HugeIcons.strokeRoundedSun01,
          selected: _theme == 'Light theme',
          onTap: () => _selectTheme('Light theme'),
        ),
        _SettingsThemeOption(
          title: 'Dark theme',
          icon: HugeIcons.strokeRoundedMoon02,
          selected: _theme == 'Dark theme',
          onTap: () => _selectTheme('Dark theme'),
        ),
      ],
    );
  }

  void _selectTheme(String theme) {
    setState(() => _theme = theme);
  }
}

class _SettingsThemeOption extends StatelessWidget {
  const _SettingsThemeOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final HugeIconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MenuComponent(
      title: title,
      leading: _CatalogHugeIcon(icon),
      selected: selected,
      trailing: selected
          ? _CatalogHugeIcon(
              HugeIcons.strokeRoundedTick02,
              color: colors.primary,
              size: IconSizes.small,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _SettingsGeneralPage extends StatefulWidget {
  const _SettingsGeneralPage();

  @override
  State<_SettingsGeneralPage> createState() => _SettingsGeneralPageState();
}

class _SettingsGeneralPageState extends State<_SettingsGeneralPage> {
  bool _largeIcons = true;
  bool _compactMode = false;
  bool _hideCodes = true;

  @override
  Widget build(BuildContext context) {
    return _SettingsExampleShell(
      title: 'General',
      children: [
        const MenuComponent(
          title: 'Language',
          subtitle: 'English',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedLanguageSquare),
          trailing: _SettingsTrailingIcon(),
        ),
        _SettingsToggleItem(
          title: 'Show large icons',
          icon: HugeIcons.strokeRoundedImage02,
          selected: _largeIcons,
          onChanged: (value) => setState(() => _largeIcons = value),
        ),
        _SettingsToggleItem(
          title: 'Compact mode',
          icon: HugeIcons.strokeRoundedLayoutTable01,
          selected: _compactMode,
          onChanged: (value) => setState(() => _compactMode = value),
        ),
        _SettingsToggleItem(
          title: 'Hide codes',
          icon: HugeIcons.strokeRoundedViewOff,
          selected: _hideCodes,
          onChanged: (value) => setState(() => _hideCodes = value),
        ),
      ],
    );
  }
}

class _SettingsToggleItem extends StatelessWidget {
  const _SettingsToggleItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final HugeIconData icon;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuComponent(
      title: title,
      leading: _CatalogHugeIcon(icon),
      trailing: ToggleSwitchComponent(selected: selected, onChanged: onChanged),
    );
  }
}

class _SettingsSupportPage extends StatelessWidget {
  const _SettingsSupportPage();

  @override
  Widget build(BuildContext context) {
    return const _SettingsExampleShell(
      title: 'Help and support',
      children: [
        MenuComponent(
          title: 'Contact support',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedCustomerSupport),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Help',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedHelpCircle),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Suggest features',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedBulb),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Report a bug',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedBug02),
          trailing: _SettingsTrailingIcon(),
        ),
      ],
    );
  }
}

class _SettingsAboutPage extends StatelessWidget {
  const _SettingsAboutPage();

  @override
  Widget build(BuildContext context) {
    return const _SettingsExampleShell(
      title: 'About',
      children: [
        MenuComponent(
          title: 'Open source',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedGithub),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Privacy',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedShield01),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Terms of service',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedNote),
          trailing: _SettingsTrailingIcon(),
        ),
        MenuComponent(
          title: 'Check for updates',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedRefresh),
          trailing: _SettingsTrailingIcon(),
        ),
      ],
    );
  }
}

class _TextStylesPreview extends StatelessWidget {
  const _TextStylesPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return _CatalogPreviewGroup(
      title: 'Type scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'H1 / 20 / 28 / Bold',
            style: TextStyles.h1,
            color: colors.textBase,
          ),
          const SizedBox(height: Spacing.xl),
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'H2 / 18 / 24 / Semi Bold',
            style: TextStyles.h2,
            color: colors.textBase,
          ),
          const SizedBox(height: Spacing.xl),
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'Large / 16 / 20 / Semi Bold',
            style: TextStyles.large,
            color: colors.textBase,
          ),
          const SizedBox(height: Spacing.xl),
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'Body / 14 / 20 / Medium',
            style: TextStyles.body,
            color: colors.textBase,
          ),
          const SizedBox(height: Spacing.xl),
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'Mini / 12 / 16 / Medium',
            style: TextStyles.mini,
            color: colors.textLight,
          ),
          const SizedBox(height: Spacing.xl),
          _TypeSample(
            text: 'Secure backup is ready',
            detail: 'Tiny / 10 / 12 / Medium',
            style: TextStyles.tiny,
            color: colors.textLight,
          ),
        ],
      ),
    );
  }
}

class _TypeSample extends StatelessWidget {
  const _TypeSample({
    required this.text,
    required this.detail,
    required this.style,
    required this.color,
  });

  final String text;
  final String detail;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: style.copyWith(color: color)),
        const SizedBox(height: Spacing.xs),
        Text(detail, style: TextStyles.mini.copyWith(color: colors.textLight)),
      ],
    );
  }
}

const _bannerPreviewSpecs = [
  _BannerPreviewSpec(
    state: BannerComponentState.failure,
    title: 'Failure!',
    subtitle: 'Some subtext that describes the failure',
  ),
  _BannerPreviewSpec(
    state: BannerComponentState.informative,
    title: 'Informative!',
    subtitle: 'Some subtext that describes the info',
  ),
  _BannerPreviewSpec(
    state: BannerComponentState.success,
    title: 'Success!',
    subtitle: 'Some subtext that describes the success',
  ),
  _BannerPreviewSpec(
    state: BannerComponentState.warning,
    title: 'Warning!',
    subtitle: 'Some subtext that describes the warning',
  ),
  _BannerPreviewSpec(
    state: BannerComponentState.neutral,
    title: 'Neutral!',
    subtitle: 'Some subtext that describes the neutral text',
  ),
];

class _BannerPreviewSpec {
  const _BannerPreviewSpec({
    required this.state,
    required this.title,
    required this.subtitle,
  });

  final BannerComponentState state;
  final String title;
  final String subtitle;
}

class _BannerPreview extends StatelessWidget {
  const _BannerPreview();

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'States',
          child: Column(
            children: [
              for (
                var index = 0;
                index < _bannerPreviewSpecs.length;
                index++
              ) ...[
                _BannerStatePreview(spec: _bannerPreviewSpecs[index]),
                if (index != _bannerPreviewSpecs.length - 1)
                  const SizedBox(height: Spacing.md),
              ],
            ],
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Custom leading',
          child: BannerComponent(
            title: 'Syncing backup',
            subtitle: 'Preparing secure upload',
            state: BannerComponentState.informative,
            leadingWidget: const _BannerLoadingLeading(),
            onTap: () {},
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Custom trailing',
          child: BannerComponent(
            title: 'Dismissible info',
            subtitle: 'Some subtext with a custom trailing icon',
            state: BannerComponentState.informative,
            trailingWidget: const _CatalogHugeIcon(
              HugeIcons.strokeRoundedCancel01,
              size: IconSizes.small,
            ),
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _BannerLoadingLeading extends StatelessWidget {
  const _BannerLoadingLeading();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return SizedBox(
      width: IconSizes.small,
      height: IconSizes.small,
      child: CircularProgressIndicator(color: colors.blue, strokeWidth: 2),
    );
  }
}

class _BannerStatePreview extends StatelessWidget {
  const _BannerStatePreview({required this.spec});

  final _BannerPreviewSpec spec;

  @override
  Widget build(BuildContext context) {
    return BannerComponent(
      title: spec.title,
      subtitle: spec.subtitle,
      state: spec.state,
      onTap: () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${spec.title} tapped')));
      },
    );
  }
}

const _toastStateSpecs = [
  _ToastStateSpec(
    state: BannerComponentState.failure,
    label: 'Failure',
    title: 'Failure!',
    subtitle: 'Some subtext that describes the failure',
  ),
  _ToastStateSpec(
    state: BannerComponentState.informative,
    label: 'Informative',
    title: 'Informative!',
    subtitle: 'Some subtext that describes the info',
  ),
  _ToastStateSpec(
    state: BannerComponentState.success,
    label: 'Success',
    title: 'Success!',
    subtitle: 'Some subtext that describes the success',
  ),
  _ToastStateSpec(
    state: BannerComponentState.warning,
    label: 'Warning',
    title: 'Warning!',
    subtitle: 'Some subtext that describes the warning',
  ),
  _ToastStateSpec(
    state: BannerComponentState.neutral,
    label: 'Neutral',
    title: 'Neutral!',
    subtitle: 'Some subtext that describes the neutral text',
  ),
];

class _ToastStateSpec {
  const _ToastStateSpec({
    required this.state,
    required this.label,
    required this.title,
    required this.subtitle,
  });

  final BannerComponentState state;
  final String label;
  final String title;
  final String subtitle;
}

class _ToastPreview extends StatelessWidget {
  const _ToastPreview();

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'States (tap to show)',
          child: Column(
            children: [
              for (var index = 0; index < _toastStateSpecs.length; index++) ...[
                _ToastTriggerButton(
                  label: 'Show ${_toastStateSpecs[index].label.toLowerCase()}',
                  onTap: () => showToastComponent(
                    context,
                    _toastStateSpecs[index].title,
                    subtitle: _toastStateSpecs[index].subtitle,
                    state: _toastStateSpecs[index].state,
                  ),
                ),
                if (index != _toastStateSpecs.length - 1)
                  const SizedBox(height: Spacing.sm),
              ],
            ],
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Title only',
          child: _ToastTriggerButton(
            label: 'Show title-only toast',
            onTap: () => showToastComponent(context, 'Saved to your library'),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Custom leading (spinner)',
          child: _ToastTriggerButton(
            label: 'Show custom leading',
            onTap: () => showToastComponent(
              context,
              'Syncing your data',
              subtitle: 'Preparing secure upload',
              state: BannerComponentState.informative,
              leadingWidget: const _BannerLoadingLeading(),
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Custom trailing',
          child: _ToastTriggerButton(
            label: 'Show custom trailing',
            onTap: () => showToastComponent(
              context,
              'Item moved to trash',
              subtitle: 'Tap the icon to undo',
              state: BannerComponentState.neutral,
              trailingWidget: const _CatalogHugeIcon(
                HugeIcons.strokeRoundedDelete02,
                size: IconSizes.small,
              ),
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Duration (short vs long)',
          child: Column(
            children: [
              _ToastTriggerButton(
                label: 'Short (2s)',
                onTap: () => showToastComponent(
                  context,
                  'Short toast (2s)',
                  state: BannerComponentState.informative,
                  duration: const Duration(seconds: 2),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              _ToastTriggerButton(
                label: 'Long (default 4s)',
                onTap: () => showToastComponent(
                  context,
                  'Long toast (4s)',
                  state: BannerComponentState.informative,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastTriggerButton extends StatelessWidget {
  const _ToastTriggerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ButtonComponent(
      variant: ButtonComponentVariant.secondary,
      label: label,
      shouldSurfaceExecutionStates: false,
      onTap: onTap,
    );
  }
}

class _ButtonMatrix extends StatelessWidget {
  const _ButtonMatrix();

  @override
  Widget build(BuildContext context) {
    return const _CatalogPreviewList(
      children: [
        ButtonStateCyclePreview(),
        _ButtonExecutionPreview(),
        _ButtonStateGroup(title: 'Default'),
        _ButtonStateGroup(title: 'Disabled', disabled: true),
        _CatalogPreviewGroup(
          title: 'Icon button async actions',
          child: _IconButtonMatrix(),
        ),
      ],
    );
  }
}

class ButtonStateCyclePreview extends StatefulWidget {
  const ButtonStateCyclePreview({super.key});

  @override
  State<ButtonStateCyclePreview> createState() =>
      _ButtonStateCyclePreviewState();
}

class _ButtonStateCyclePreviewState extends State<ButtonStateCyclePreview> {
  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewGroup(
      title: 'State transition',
      child: ButtonComponent(
        key: const ValueKey('button-cycle'),
        label: 'Continue',
        variant: ButtonComponentVariant.primary,
        size: ButtonComponentSize.large,
        onTap: _runPreviewAction,
      ),
    );
  }

  Future<void> _runPreviewAction() {
    return Future<void>.delayed(const Duration(milliseconds: 900));
  }
}

class _ButtonExecutionPreview extends StatelessWidget {
  const _ButtonExecutionPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return _CatalogPreviewGroup(
      title: 'Async actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Success',
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.xs),
          ButtonComponent(
            label: 'Save changes',
            variant: ButtonComponentVariant.primary,
            size: ButtonComponentSize.large,
            onTap: () =>
                Future<void>.delayed(const Duration(milliseconds: 900)),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Error',
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.xs),
          ButtonComponent(
            label: 'Sync backup',
            variant: ButtonComponentVariant.critical,
            size: ButtonComponentSize.large,
            onTap: () => _runPreviewError(context),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Fast confirmation',
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.xs),
          ButtonComponent(
            label: 'Copy link',
            variant: ButtonComponentVariant.secondary,
            size: ButtonComponentSize.large,
            shouldShowSuccessConfirmation: true,
            onTap: () =>
                Future<void>.delayed(const Duration(milliseconds: 120)),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Surface off',
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
          const SizedBox(height: Spacing.xs),
          ButtonComponent(
            label: 'Refresh',
            variant: ButtonComponentVariant.neutral,
            size: ButtonComponentSize.large,
            shouldSurfaceExecutionStates: false,
            onTap: () =>
                Future<void>.delayed(const Duration(milliseconds: 900)),
          ),
        ],
      ),
    );
  }

  Future<void> _runPreviewError(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    }
    throw StateError('Preview action failed');
  }
}

const _buttonPreviewSpecs = <_ButtonPreviewSpec>[
  _ButtonPreviewSpec(
    type: 'Primary',
    label: 'Continue',
    variant: ButtonComponentVariant.primary,
  ),
  _ButtonPreviewSpec(
    type: 'Secondary',
    label: 'Cancel',
    variant: ButtonComponentVariant.secondary,
  ),
  _ButtonPreviewSpec(
    type: 'Neutral',
    label: 'Use recovery key',
    variant: ButtonComponentVariant.neutral,
  ),
  _ButtonPreviewSpec(
    type: 'Critical',
    label: 'Delete account',
    variant: ButtonComponentVariant.critical,
  ),
  _ButtonPreviewSpec(
    type: 'Tertiary critical',
    label: 'Remove trusted contact',
    variant: ButtonComponentVariant.tertiaryCritical,
  ),
  _ButtonPreviewSpec(
    type: 'Link button',
    label: 'Forgot password?',
    variant: ButtonComponentVariant.link,
  ),
];

class _ButtonPreviewSpec {
  const _ButtonPreviewSpec({
    required this.type,
    required this.label,
    required this.variant,
  });

  final String type;
  final String label;
  final ButtonComponentVariant variant;
}

class _ButtonStateGroup extends StatelessWidget {
  const _ButtonStateGroup({required this.title, this.disabled = false});

  final String title;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewGroup(
      title: title,
      child: Column(
        children: [
          for (var index = 0; index < _buttonPreviewSpecs.length; index++) ...[
            _ButtonPreviewRow(
              spec: _buttonPreviewSpecs[index],
              disabled: disabled,
            ),
            if (index != _buttonPreviewSpecs.length - 1)
              const SizedBox(height: Spacing.md),
          ],
        ],
      ),
    );
  }
}

class _ButtonPreviewRow extends StatelessWidget {
  const _ButtonPreviewRow({required this.spec, required this.disabled});

  final _ButtonPreviewSpec spec;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spec.type,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.xs),
        ButtonComponent(
          label: spec.label,
          variant: spec.variant,
          size: ButtonComponentSize.large,
          onTap: disabled ? null : () {},
        ),
      ],
    );
  }
}

class _IconButtonMatrix extends StatelessWidget {
  const _IconButtonMatrix();

  @override
  Widget build(BuildContext context) {
    const columns = ['Default', 'Disabled', 'Loading', 'Success', 'Error'];
    const rows = [
      _IconButtonPreviewRow(
        label: 'Primary',
        variant: IconButtonComponentVariant.primary,
      ),
      _IconButtonPreviewRow(
        label: 'Critical',
        variant: IconButtonComponentVariant.critical,
      ),
      _IconButtonPreviewRow(
        label: 'Unfilled',
        variant: IconButtonComponentVariant.unfilled,
      ),
      _IconButtonPreviewRow(
        label: 'Secondary',
        variant: IconButtonComponentVariant.secondary,
      ),
      _IconButtonPreviewRow(
        label: 'Green',
        variant: IconButtonComponentVariant.green,
      ),
      _IconButtonPreviewRow(
        label: 'Circular',
        variant: IconButtonComponentVariant.circular,
      ),
    ];
    final colors = context.componentColors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 84),
              for (final column in columns)
                SizedBox(
                  width: 76,
                  child: Text(
                    column,
                    textAlign: TextAlign.center,
                    style: TextStyles.large.copyWith(color: colors.textBase),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          for (final row in rows) ...[
            row,
            if (row != rows.last) const SizedBox(height: Spacing.md),
          ],
        ],
      ),
    );
  }
}

class _IconButtonPreviewRow extends StatelessWidget {
  const _IconButtonPreviewRow({required this.label, required this.variant});

  final String label;
  final IconButtonComponentVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
        ),
        for (final state in const [
          'Default',
          'Disabled',
          'Loading',
          'Success',
          'Error',
        ])
          SizedBox(
            width: 76,
            child: Center(
              child: _IconButtonStatePreview(variant: variant, state: state),
            ),
          ),
      ],
    );
  }
}

class _IconButtonStatePreview extends StatelessWidget {
  const _IconButtonStatePreview({required this.variant, required this.state});

  final IconButtonComponentVariant variant;
  final String state;

  @override
  Widget build(BuildContext context) {
    return IconButtonComponent(
      tooltip: state,
      variant: variant,
      shouldShowSuccessConfirmation: state == 'Success',
      onTap: state == 'Disabled'
          ? null
          : state == 'Loading'
          ? () => Future<void>.delayed(const Duration(milliseconds: 900))
          : state == 'Success'
          ? () => Future<void>.delayed(const Duration(milliseconds: 120))
          : state == 'Error'
          ? () => _runPreviewError(context)
          : () {},
      icon: const _CatalogHugeIcon(
        HugeIcons.strokeRoundedAdd01,
        size: IconSizes.small,
      ),
    );
  }

  Future<void> _runPreviewError(BuildContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
    }
    throw StateError('Preview action failed');
  }
}

class _FilterChipPreview extends StatefulWidget {
  const _FilterChipPreview();

  @override
  State<_FilterChipPreview> createState() => _FilterChipPreviewState();
}

class _FilterChipPreviewState extends State<_FilterChipPreview> {
  final Set<String> _selected = {'Faces', 'Favorites'};

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Editable',
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _EditableChip(
                label: 'Faces',
                selected: _selected.contains('Faces'),
                onChanged: _toggle('Faces'),
                avatar: const _FaceAvatar(seed: 0, initials: 'AR'),
              ),
              _EditableChip(
                label: 'Favorites',
                selected: _selected.contains('Favorites'),
                onChanged: _toggle('Favorites'),
                leading: const _CatalogHugeIcon(HugeIcons.strokeRoundedStar),
              ),
              _EditableChip(
                label: 'Videos',
                selected: _selected.contains('Videos'),
                onChanged: _toggle('Videos'),
                trailing: const _CatalogHugeIcon(
                  HugeIcons.strokeRoundedVideo01,
                ),
              ),
            ],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'States',
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              FilterChipComponent(
                label: 'Selected',
                state: FilterChipComponentState.selected,
              ),
              FilterChipComponent(
                label: 'Unselected',
                state: FilterChipComponentState.unselected,
              ),
              FilterChipComponent(
                label: 'Disabled',
                state: FilterChipComponentState.disabled,
              ),
            ],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Icons',
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              FilterChipComponent(
                label: 'Albums',
                leading: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.selected,
              ),
              FilterChipComponent(
                label: 'Shared',
                leading: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.unselected,
              ),
              FilterChipComponent(
                label: 'Archived',
                leading: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.disabled,
              ),
              FilterChipComponent(
                label: 'Recent',
                trailing: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.selected,
              ),
              FilterChipComponent(
                label: 'Places',
                trailing: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.unselected,
              ),
              FilterChipComponent(
                label: 'Hidden',
                trailing: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                state: FilterChipComponentState.disabled,
              ),
            ],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Faces',
          child: Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              FilterChipComponent(
                label: 'Aarav',
                avatar: _FaceAvatar(seed: 0, initials: 'AR'),
                state: FilterChipComponentState.selected,
              ),
              FilterChipComponent(
                label: 'Mira',
                avatar: _FaceAvatar(seed: 1, initials: 'MR'),
                state: FilterChipComponentState.unselected,
              ),
              FilterChipComponent(
                label: 'Nila',
                avatar: _FaceAvatar(seed: 2, initials: 'NS'),
                state: FilterChipComponentState.disabled,
              ),
              FilterChipComponent(
                avatar: _FaceAvatar(seed: 3, initials: 'KV'),
                state: FilterChipComponentState.selected,
              ),
              FilterChipComponent(
                avatar: _FaceAvatar(seed: 1, initials: 'MR'),
                state: FilterChipComponentState.unselected,
              ),
              FilterChipComponent(
                avatar: _FaceAvatar(seed: 2, initials: 'NS'),
                state: FilterChipComponentState.disabled,
              ),
            ],
          ),
        ),
      ],
    );
  }

  ValueChanged<bool> _toggle(String label) {
    return (selected) {
      setState(() {
        if (selected) {
          _selected.add(label);
        } else {
          _selected.remove(label);
        }
      });
    };
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview();

  static const _sizes = [
    (label: 'XS', size: AvatarComponentSize.xs),
    (label: 'Small', size: AvatarComponentSize.small),
    (label: 'Default', size: AvatarComponentSize.defaultSize),
    (label: 'Medium', size: AvatarComponentSize.medium),
    (label: 'Large', size: AvatarComponentSize.large),
    (label: 'Contact (huge)', size: AvatarComponentSize.contactHuge),
  ];
  static const _colors = [
    (label: 'Yellow', color: AvatarComponentColor.yellow, initials: 'E'),
    (label: 'Green', color: AvatarComponentColor.green, initials: 'K'),
    (label: 'Orange', color: AvatarComponentColor.orange, initials: 'T'),
    (label: 'Pink', color: AvatarComponentColor.pink, initials: 'U'),
    (label: 'Purple', color: AvatarComponentColor.purple, initials: 'R'),
    (label: 'Blue', color: AvatarComponentColor.blue, initials: 'S'),
    (label: 'Cyan', color: AvatarComponentColor.cyan, initials: 'C'),
  ];

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Variants and sizes',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _AvatarTableHeader(sizes: _sizes),
                const SizedBox(height: Spacing.lg),
                for (final item in _colors) ...[
                  _AvatarTableRow(
                    label: item.label,
                    children: [
                      for (final size in _sizes)
                        AvatarComponent(
                          initials: item.initials,
                          color: item.color,
                          size: size.size,
                        ),
                    ],
                  ),
                  if (item != _colors.last) const SizedBox(height: Spacing.md),
                ],
                const SizedBox(height: Spacing.md),
                const _AvatarTableRow(
                  label: 'Add icon',
                  children: [
                    SizedBox.shrink(),
                    SizedBox.shrink(),
                    SizedBox.shrink(),
                    SizedBox.shrink(),
                    SizedBox.shrink(),
                    AvatarComponent.icon(
                      icon: _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Seed palette',
          child: Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.md,
            children: [
              for (var index = 0; index < avatarLight.length; index++)
                AvatarComponent.seeded(
                  initials: String.fromCharCode(65 + index % 26),
                  seed: index,
                  size: AvatarComponentSize.large,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvatarTableHeader extends StatelessWidget {
  const _AvatarTableHeader({required this.sizes});

  final List<({String label, AvatarComponentSize size})> sizes;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        const SizedBox(width: 92),
        for (final size in sizes)
          SizedBox(
            width: 96,
            child: Text(
              size.label,
              textAlign: TextAlign.center,
              style: TextStyles.large.copyWith(color: colors.textBase),
            ),
          ),
      ],
    );
  }
}

class _AvatarTableRow extends StatelessWidget {
  const _AvatarTableRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyles.large.copyWith(color: colors.textBase),
          ),
        ),
        for (final child in children)
          SizedBox(width: 96, height: 64, child: Center(child: child)),
      ],
    );
  }
}

class _EditableChip extends StatelessWidget {
  const _EditableChip({
    required this.label,
    required this.selected,
    required this.onChanged,
    this.leading,
    this.trailing,
    this.avatar,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final Widget? leading;
  final Widget? trailing;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return FilterChipComponent(
      label: label,
      leading: leading,
      trailing: trailing,
      avatar: avatar,
      state: selected
          ? FilterChipComponentState.selected
          : FilterChipComponentState.unselected,
      onChanged: onChanged,
    );
  }
}

class _FaceAvatar extends StatelessWidget {
  const _FaceAvatar({required this.seed, required this.initials});

  final int seed;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return AvatarComponent.seeded(
      initials: initials,
      seed: seed,
      size: AvatarComponentSize.large,
    );
  }
}

class _TextInputPreview extends StatefulWidget {
  const _TextInputPreview();

  @override
  State<_TextInputPreview> createState() => _TextInputPreviewState();
}

class _TextInputPreviewState extends State<_TextInputPreview> {
  late final TextEditingController _focusedController;
  late final TextEditingController _errorController;
  late final TextEditingController _successController;
  late final TextEditingController _disabledController;
  late final TextEditingController _clearableController;
  late final TextEditingController _passwordController;
  late final TextEditingController _submitController;
  late final ValueNotifier<int> _submitNotifier;

  @override
  void initState() {
    super.initState();
    _focusedController = TextEditingController(text: 'mira@example.com');
    _errorController = TextEditingController(text: 'short');
    _successController = TextEditingController(text: '482901');
    _disabledController = TextEditingController(text: 'mira.roy@example.com');
    _clearableController = TextEditingController(text: 'family trip');
    _passwordController = TextEditingController(text: 'correct horse');
    _submitController = TextEditingController(text: 'wrong password');
    _submitNotifier = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _focusedController.dispose();
    _errorController.dispose();
    _successController.dispose();
    _disabledController.dispose();
    _clearableController.dispose();
    _passwordController.dispose();
    _submitController.dispose();
    _submitNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        const _CatalogPreviewGroup(
          title: 'Normal',
          child: TextInputComponent(
            label: 'Email address',
            hintText: 'Hint text',
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Focused',
          child: TextInputComponent(
            controller: _focusedController,
            label: 'Email address',
            prefix: const _TextInputPreviewIcon(HugeIcons.strokeRoundedMail01),
            suffix: const _TextInputPreviewIcon(HugeIcons.strokeRoundedView),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Error',
          child: TextInputComponent(
            controller: _errorController,
            label: 'Password',
            message: 'Use at least 8 characters.',
            messageType: TextInputComponentMessageType.error,
            isPasswordInput: true,
            prefix: const _TextInputPreviewIcon(
              HugeIcons.strokeRoundedLockPassword,
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Submit error',
          child: Column(
            children: [
              TextInputComponent(
                controller: _submitController,
                submitNotifier: _submitNotifier,
                label: 'Password',
                hintText: 'Enter password',
                isPasswordInput: true,
                popNavAfterSubmission: true,
                prefix: const _TextInputPreviewIcon(
                  HugeIcons.strokeRoundedLockPassword,
                ),
                onSubmit: (_) async {
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  throw Exception('Incorrect password');
                },
              ),
              const SizedBox(height: Spacing.md),
              ButtonComponent(
                label: 'Submit',
                size: ButtonComponentSize.small,
                shouldSurfaceExecutionStates: false,
                onTap: () {
                  _submitNotifier.value++;
                },
              ),
            ],
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Success',
          child: TextInputComponent(
            controller: _successController,
            label: 'Recovery code',
            message: 'Recovery code verified.',
            messageType: TextInputComponentMessageType.success,
            suffix: const _TextInputPreviewIcon(
              HugeIcons.strokeRoundedCheckmarkCircle01,
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Disabled',
          child: TextInputComponent(
            controller: _disabledController,
            label: 'Account email',
            isDisabled: true,
            prefix: const _TextInputPreviewIcon(HugeIcons.strokeRoundedMail01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'No label',
          child: TextInputComponent(hintText: 'Hint text'),
        ),
        const _CatalogPreviewGroup(
          title: 'Required',
          child: TextInputComponent(
            label: 'Email address',
            hintText: 'mira@example.com',
            isRequired: true,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Helper text',
          child: TextInputComponent(
            label: 'Recovery email',
            hintText: 'mira@example.com',
            message: 'Used for receipts and security alerts.',
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Prefix icon',
          child: TextInputComponent(
            label: 'Search',
            hintText: 'Search albums',
            prefix: _TextInputPreviewIcon(HugeIcons.strokeRoundedSearch01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Trailing icon',
          child: TextInputComponent(
            label: 'Password',
            hintText: 'Enter password',
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedView),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Prefix and trailing icons',
          child: TextInputComponent(
            label: 'Search',
            hintText: 'Search people',
            prefix: _TextInputPreviewIcon(HugeIcons.strokeRoundedSearch01),
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCancel01),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Clearable search',
          child: TextInputComponent(
            controller: _clearableController,
            label: 'Search',
            hintText: 'Search files',
            prefix: const _TextInputPreviewIcon(
              HugeIcons.strokeRoundedSearch01,
            ),
            isClearable: true,
            autocorrect: false,
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Password visibility',
          child: TextInputComponent(
            controller: _passwordController,
            label: 'Password',
            hintText: 'Enter password',
            isPasswordInput: true,
            prefix: const _TextInputPreviewIcon(
              HugeIcons.strokeRoundedLockPassword,
            ),
            autofillHints: const [AutofillHints.password],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Alert message',
          child: TextInputComponent(
            label: 'Recovery key',
            hintText: 'Enter recovery key',
            message: 'Save this key somewhere safe before continuing.',
            messageType: TextInputComponentMessageType.alert,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Max length',
          child: TextInputComponent(
            label: 'Referral code',
            hintText: 'SUMMER2026',
            maxLength: 12,
            textCapitalization: TextCapitalization.characters,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: label + trailing + warning message',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            message: 'This is an error',
            messageType: TextInputComponentMessageType.error,
            maxLines: 4,
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCopy01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: label + trailing',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCopy01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: label only',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: no label + trailing',
          child: TextInputComponent(
            hintText: 'Hint text',
            maxLines: 4,
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCopy01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: no label',
          child: TextInputComponent(hintText: 'Hint text', maxLines: 4),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: focused',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCopy01),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: error',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
            message: 'This is an error',
            messageType: TextInputComponentMessageType.error,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: success',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
            message: 'Saved',
            messageType: TextInputComponentMessageType.success,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Multiline: disabled',
          child: TextInputComponent(
            label: 'Description',
            hintText: 'Hint text',
            maxLines: 4,
            isDisabled: true,
            suffix: _TextInputPreviewIcon(HugeIcons.strokeRoundedCopy01),
          ),
        ),
      ],
    );
  }
}

class _TextInputPreviewIcon extends StatelessWidget {
  const _TextInputPreviewIcon(this.icon);

  final HugeIconData icon;

  @override
  Widget build(BuildContext context) {
    return _CatalogHugeIcon(icon, color: context.componentColors.textLighter);
  }
}

class _HeaderImage extends StatelessWidget {
  const _HeaderImage();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return ColoredBox(
      color: colors.fillDark,
      child: Center(
        child: _CatalogHugeIcon(
          HugeIcons.strokeRoundedUser,
          color: colors.textLight,
          size: IconSizes.small,
        ),
      ),
    );
  }
}

class _HeaderAppBarEntryPreview extends StatelessWidget {
  const _HeaderAppBarEntryPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Text(
      'Open this section from the catalog list to test the pinned animated '
      'header app bar with a long scrollable list.',
      style: TextStyles.body.copyWith(color: colors.textLight),
    );
  }
}

class _TooltipPreview extends StatelessWidget {
  const _TooltipPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Top pointer',
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.fillDarker,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: const Padding(
              padding: EdgeInsets.all(Spacing.xl),
              child: TooltipBubbleComponent(message: 'Tooltip text'),
            ),
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Tap triggers',
          child: Column(
            children: [
              _TooltipTriggerRow(
                title: 'Short',
                subtitle: 'Compact bubble',
                message: 'Tooltip',
                colors: colors,
              ),
              const SizedBox(height: Spacing.sm),
              _TooltipTriggerRow(
                title: 'Medium title',
                subtitle: 'Normal app title length',
                message: 'Whatsapp video long long long name',
                colors: colors,
              ),
              const SizedBox(height: Spacing.sm),
              _TooltipTriggerRow(
                title: 'Long email',
                subtitle: 'Tests email wrapping points',
                message:
                    'alexandra.rivera.photo.archive.longtitle.test@examplemail.com',
                colors: colors,
              ),
              const SizedBox(height: Spacing.sm),
              _TooltipTriggerRow(
                title: 'Overflow',
                subtitle: 'Caps at max width and ellipsizes',
                message:
                    'This is an intentionally very long tooltip message that should wrap up to three lines and then ellipsize cleanly without covering the full screen.',
                maxWidth: 240,
                colors: colors,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TooltipTriggerRow extends StatelessWidget {
  const _TooltipTriggerRow({
    required this.title,
    required this.subtitle,
    required this.message,
    required this.colors,
    this.maxWidth = 320,
  });

  final String title;
  final String subtitle;
  final String message;
  final ColorTokens colors;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return TooltipComponent(
      message: message,
      maxWidth: maxWidth,
      child: MenuComponent(
        title: title,
        subtitle: subtitle,
        leading: const _CatalogHugeIcon(HugeIcons.strokeRoundedHelpCircle),
        trailing: _CatalogHugeIcon(
          HugeIcons.strokeRoundedArrowRight02,
          color: colors.textLight,
          size: IconSizes.small,
        ),
      ),
    );
  }
}

class HeaderAppBarDemoPage extends StatefulWidget {
  const HeaderAppBarDemoPage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<HeaderAppBarDemoPage> createState() => _HeaderAppBarDemoPageState();
}

enum _HeaderTitleRevealVariant { tooltip, disabled }

class _HeaderAppBarDemoPageState extends State<HeaderAppBarDemoPage> {
  static const _itemCount = 48;
  static const _longTitle =
      'alexandra.rivera.photo.archive.longtitle.test@examplemail.com';

  late ThemeMode _themeMode = widget.themeMode;
  _HeaderTitleRevealVariant _titleRevealVariant =
      _HeaderTitleRevealVariant.tooltip;

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  void _setTitleRevealVariant(_HeaderTitleRevealVariant variant) {
    setState(() => _titleRevealVariant = variant);
  }

  void _showAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final titleRevealVariant = _titleRevealVariant;
    final disableTitleTapReveal =
        titleRevealVariant != _HeaderTitleRevealVariant.tooltip;
    final actions = <Widget>[
      IconButtonComponent(
        tooltip: 'Add item',
        variant: IconButtonComponentVariant.primary,
        icon: const _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
        onTap: () => _showAction('Add tapped'),
      ),
      _CatalogThemeCycleButton(themeMode: _themeMode, onChanged: _setThemeMode),
    ];

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: AppBarComponent(
        title: _longTitle,
        disableTitleTapReveal: disableTitleTapReveal,
        subtitle: titleRevealVariant.description,
        onBack: () => Navigator.of(context).pop(),
        leading: const _HeaderAppBarDemoLeading(),
        actions: actions,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: _HeaderAppBarTitleRevealControls(
                variant: titleRevealVariant,
                onVariantChanged: _setTitleRevealVariant,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.xxl,
            ),
            sliver: SliverList.builder(
              itemCount: _itemCount * 2 - 1,
              itemBuilder: (context, index) {
                if (index.isOdd) {
                  return const SizedBox(height: Spacing.md);
                }
                return _HeaderAppBarDemoListItem(index: index ~/ 2);
              },
            ),
          ),
        ],
      ),
    );
  }
}

extension on _HeaderTitleRevealVariant {
  String get label => switch (this) {
    _HeaderTitleRevealVariant.tooltip => 'Tap popup',
    _HeaderTitleRevealVariant.disabled => 'Disabled',
  };

  String get description => switch (this) {
    _HeaderTitleRevealVariant.tooltip =>
      'Default: tap title to show the full value in a popup',
    _HeaderTitleRevealVariant.disabled =>
      'Title tap reveal disabled for this screen',
  };
}

class _HeaderAppBarTitleRevealControls extends StatelessWidget {
  const _HeaderAppBarTitleRevealControls({
    required this.variant,
    required this.onVariantChanged,
  });

  final _HeaderTitleRevealVariant variant;
  final ValueChanged<_HeaderTitleRevealVariant> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return _CatalogPreviewGroup(
      title: 'Title tap behavior',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final option in _HeaderTitleRevealVariant.values)
                FilterChipComponent(
                  label: option.label,
                  state: option == variant
                      ? FilterChipComponentState.selected
                      : FilterChipComponentState.unselected,
                  onChanged: (_) => onVariantChanged(option),
                ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Text(
            variant.description,
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ],
      ),
    );
  }
}

class _HeaderAppBarDemoLeading extends StatelessWidget {
  const _HeaderAppBarDemoLeading();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.primary),
      child: Center(
        child: _CatalogHugeIcon(
          HugeIcons.strokeRoundedMenuCircle,
          color: colors.specialWhite,
          size: IconSizes.small,
        ),
      ),
    );
  }
}

class _HeaderAppBarDemoListItem extends StatelessWidget {
  const _HeaderAppBarDemoListItem({required this.index});

  final int index;

  static const _titles = [
    'Camera uploads',
    'Private albums',
    'Recovery key',
    'Shared links',
    'Device folders',
    'Storage plan',
    'Notifications',
    'Hidden items',
    'Trash cleanup',
    'Export data',
  ];

  static const _subtitles = [
    'Enabled on Wi-Fi',
    'Only visible to you',
    'Last checked today',
    'Manage public access',
    'Choose folders to sync',
    'Family plan active',
    'Activity and reminders',
    'Protected by device lock',
    'Auto-delete in 30 days',
    'Prepare local archive',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasSubtitle = index % 3 != 1;
    final hasImage = index % 4 == 0 || index % 4 == 3;
    final hasAction = index % 5 != 2;
    final title = _titles[index % _titles.length];
    final subtitle = _subtitles[index % _subtitles.length];

    return MenuComponent(
      title: '$title ${index + 1}',
      subtitle: hasSubtitle ? subtitle : null,
      leading: hasImage ? const _HeaderImage() : null,
      trailing: hasAction
          ? IconButtonComponent(
              tooltip: 'Add $title',
              variant: IconButtonComponentVariant.primary,
              icon: const _CatalogHugeIcon(HugeIcons.strokeRoundedAdd01),
              onTap: () {},
            )
          : const _CatalogTrailingIcon(HugeIcons.strokeRoundedArrowRight02),
      titleColor: index % 7 == 0 ? colors.primary : null,
    );
  }
}

class _SelectionPreview extends StatefulWidget {
  const _SelectionPreview();

  @override
  State<_SelectionPreview> createState() => _SelectionPreviewState();
}

class _SelectionPreviewState extends State<_SelectionPreview> {
  bool _checkbox = true;
  bool _radio = true;
  bool _switch = true;
  double _slider = 0.42;
  int _stepper = 3;

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Interactive controls',
          child: Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.md,
            children: [
              LabeledControlComponent(
                control: CheckboxComponent(
                  selected: _checkbox,
                  onChanged: (value) => setState(() => _checkbox = value),
                ),
                label: 'Checkbox',
              ),
              LabeledControlComponent(
                control: RadioComponent(
                  selected: _radio,
                  onChanged: (value) => setState(() => _radio = value),
                ),
                label: 'Radio',
              ),
              LabeledControlComponent(
                control: ToggleSwitchComponent(
                  selected: _switch,
                  onChanged: (value) => setState(() => _switch = value),
                ),
                label: 'Switch',
              ),
            ],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Disabled controls',
          child: Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.md,
            children: [
              LabeledControlComponent(
                control: CheckboxComponent(selected: true, onChanged: null),
                label: 'Selected checkbox',
              ),
              LabeledControlComponent(
                control: CheckboxComponent(selected: false, onChanged: null),
                label: 'Empty checkbox',
              ),
              LabeledControlComponent(
                control: RadioComponent(selected: true, onChanged: null),
                label: 'Selected radio',
              ),
              LabeledControlComponent(
                control: ToggleSwitchComponent(
                  selected: false,
                  onChanged: null,
                ),
                label: 'Off switch',
              ),
            ],
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Slider',
          child: SliderComponent(
            value: _slider,
            onChanged: (value) => setState(() => _slider = value),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Disabled slider',
          child: SliderComponent(value: 0.7, onChanged: null),
        ),
        _CatalogPreviewGroup(
          title: 'Stepper',
          child: StepperComponent(
            value: _stepper,
            onChanged: (value) => setState(() => _stepper = value),
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Stepper limits',
          child: Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.md,
            children: [
              StepperComponent(value: 0, min: 0, max: 5, onChanged: null),
              StepperComponent(value: 5, min: 0, max: 5, onChanged: null),
            ],
          ),
        ),
      ],
    );
  }
}

class _PopupMenuPreview extends StatefulWidget {
  const _PopupMenuPreview();

  @override
  State<_PopupMenuPreview> createState() => _PopupMenuPreviewState();
}

class _PopupMenuPreviewState extends State<_PopupMenuPreview> {
  String _lastSelection = 'None';

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Interactive menu triggers',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Spacing.md,
                runSpacing: Spacing.md,
                children: [
                  _PopupMenuTrigger(
                    optionsBuilder: _sortOptions,
                    onSelected: _handleSelected,
                  ),
                  _PopupMenuTrigger(
                    optionsBuilder: _fileOptions,
                    onSelected: _handleSelected,
                  ),
                  _PopupMenuTrigger(
                    optionsBuilder: _viewOptions,
                    onSelected: _handleSelected,
                  ),
                  _PopupMenuTrigger(
                    optionsBuilder: _fullOptions,
                    onSelected: _handleSelected,
                  ),
                  _PopupMenuTrigger(
                    optionsBuilder: _activeOptions,
                    onSelected: _handleSelected,
                  ),
                  _PopupMenuTrigger(
                    optionsBuilder: _allCasesOptions,
                    onSelected: _handleSelected,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Text(
                'Last selected: $_lastSelection',
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleSelected(String value) async {
    setState(() => _lastSelection = value);
  }

  List<EntePopupMenuOption<String>> _sortOptions(BuildContext context) {
    final colors = context.componentColors;
    return [
      EntePopupMenuOption(
        value: 'sort-name',
        label: 'Name',
        secondaryLabel: 'A-Z',
        secondaryTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedArrowUp02,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      const EntePopupMenuOption(value: 'sort-created', label: 'Created'),
      const EntePopupMenuOption(value: 'sort-newest', label: 'Newest'),
      const EntePopupMenuOption(
        value: 'sort-updated',
        label: 'Updated',
        showDivider: false,
      ),
    ];
  }

  List<EntePopupMenuOption<String>> _fileOptions(BuildContext context) {
    final colors = context.componentColors;
    return [
      const EntePopupMenuOption(
        value: 'download',
        label: 'Download',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedDownload01,
          size: IconSizes.small,
        ),
      ),
      const EntePopupMenuOption(
        value: 'share',
        label: 'Share',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedShare08,
          size: IconSizes.small,
        ),
      ),
      const EntePopupMenuOption(
        value: 'copy-link',
        label: 'Copy link',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedCopy01,
          size: IconSizes.small,
        ),
      ),
      EntePopupMenuOption(
        value: 'delete',
        label: 'Delete',
        labelColor: colors.warning,
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedDelete02,
          color: colors.warning,
          size: IconSizes.small,
        ),
        showDivider: false,
      ),
    ];
  }

  List<EntePopupMenuOption<String>> _viewOptions(BuildContext context) {
    final colors = context.componentColors;
    return [
      EntePopupMenuOption(
        value: 'grid',
        label: 'Grid',
        trailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedGridView,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      EntePopupMenuOption(
        value: 'list',
        label: 'List',
        trailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedMenu01,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      EntePopupMenuOption(
        value: 'upload',
        label: 'Upload',
        trailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedImageUpload,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
        showDivider: false,
      ),
    ];
  }

  List<EntePopupMenuOption<String>> _fullOptions(BuildContext context) {
    final colors = context.componentColors;
    return [
      EntePopupMenuOption(
        value: 'created-ascending',
        label: 'Created',
        secondaryLabel: 'A-Z',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedAdd01,
          color: colors.textLight,
          size: IconSizes.small,
        ),
        secondaryTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedArrowUp02,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
        trailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedAdd01,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      EntePopupMenuOption(
        value: 'updated-descending',
        label: 'Updated',
        secondaryLabel: 'Z-A',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedRefresh,
          color: colors.textLight,
          size: IconSizes.small,
        ),
        secondaryTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedArrowUp02,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
        activeTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedCheckmarkCircle02,
          color: colors.primary,
          size: IconSizes.tiny,
        ),
        isActive: true,
      ),
      EntePopupMenuOption(
        value: 'storage-info',
        label: 'Storage',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedDatabase,
          color: colors.textLight,
          size: IconSizes.small,
        ),
        trailingWidget: Text(
          '2 TB',
          style: TextStyles.mini.copyWith(color: colors.textLight),
        ),
        showDivider: false,
      ),
    ];
  }

  List<EntePopupMenuOption<String>> _activeOptions(BuildContext context) {
    final colors = context.componentColors;
    final activeSortIcon = _CatalogHugeIcon(
      HugeIcons.strokeRoundedArrowUp02,
      color: colors.primary,
      size: IconSizes.tiny,
    );

    return [
      EntePopupMenuOption(
        value: 'active-name',
        label: 'Name',
        secondaryLabel: 'A-Z',
        activeTrailingWidget: activeSortIcon,
        isActive: true,
      ),
      EntePopupMenuOption(
        value: 'inactive-created',
        label: 'Created',
        activeTrailingWidget: activeSortIcon,
      ),
      EntePopupMenuOption(
        value: 'inactive-updated',
        label: 'Updated',
        activeTrailingWidget: activeSortIcon,
      ),
      EntePopupMenuOption(
        value: 'inactive-size',
        label: 'Size',
        activeTrailingWidget: activeSortIcon,
        showDivider: false,
      ),
    ];
  }

  List<EntePopupMenuOption<String>> _allCasesOptions(BuildContext context) {
    final colors = context.componentColors;
    return [
      const EntePopupMenuOption(value: 'plain', label: 'Plain label'),
      const EntePopupMenuOption(
        value: 'secondary-label',
        label: 'Name',
        secondaryLabel: 'A-Z',
      ),
      EntePopupMenuOption(
        value: 'label-icon',
        label: 'Name',
        secondaryLabel: 'A-Z',
        secondaryTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedArrowUp02,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      const EntePopupMenuOption(
        value: 'leading',
        label: 'Download',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedDownload01,
          size: IconSizes.small,
        ),
      ),
      EntePopupMenuOption(
        value: 'trailing',
        label: 'Grid',
        trailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedGridView,
          color: colors.textLight,
          size: IconSizes.tiny,
        ),
      ),
      EntePopupMenuOption(
        value: 'active',
        label: 'Updated',
        secondaryLabel: 'Selected',
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedRefresh,
          color: colors.textLight,
          size: IconSizes.small,
        ),
        activeTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedCheckmarkCircle02,
          color: colors.primary,
          size: IconSizes.tiny,
        ),
        isActive: true,
      ),
      EntePopupMenuOption(
        value: 'inactive-reserved',
        label: 'Created',
        secondaryLabel: 'Not selected',
        activeTrailingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedCheckmarkCircle02,
          color: colors.primary,
          size: IconSizes.tiny,
        ),
      ),
      EntePopupMenuOption(
        value: 'destructive',
        label: 'Delete',
        labelColor: colors.warning,
        leadingWidget: _CatalogHugeIcon(
          HugeIcons.strokeRoundedDelete02,
          color: colors.warning,
          size: IconSizes.small,
        ),
        showDivider: false,
      ),
    ];
  }
}

class _PopupMenuTrigger extends StatelessWidget {
  const _PopupMenuTrigger({
    required this.optionsBuilder,
    required this.onSelected,
  });

  final List<EntePopupMenuOption<String>> Function(BuildContext context)
  optionsBuilder;
  final FutureOr<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return EntePopupMenuButton<String>(
      optionsBuilder: () => optionsBuilder(context),
      onSelected: onSelected,
    );
  }
}

enum _MenuItemTrailingKind { icon, toggle, none }

class _MenuItemPreview extends StatefulWidget {
  const _MenuItemPreview();

  @override
  State<_MenuItemPreview> createState() => _MenuItemPreviewState();
}

class _MenuItemPreviewState extends State<_MenuItemPreview> {
  bool _toggleSelected = true;

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Default',
          child: _MenuItemMatrix(
            toggleSelected: _toggleSelected,
            onToggleChanged: _setToggleSelected,
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Selected',
          child: _MenuItemMatrix(
            selected: true,
            toggleSelected: _toggleSelected,
            onToggleChanged: _setToggleSelected,
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Interaction states',
          child: _MenuItemInteractionStatesPreview(),
        ),
        _CatalogPreviewGroup(
          title: 'Display only',
          child: Builder(
            builder: (context) {
              final colors = context.componentColors;
              return MenuComponent(
                title: 'Storage plan',
                subtitle: 'Gestures disabled for read-only rows',
                leading: const _CatalogHugeIcon(
                  HugeIcons.strokeRoundedDatabase,
                ),
                trailing: Text(
                  '2 TB',
                  style: TextStyles.body.copyWith(color: colors.textLight),
                ),
                isDisabled: true,
              );
            },
          ),
        ),
        _CatalogPreviewGroup(
          title: 'Destructive',
          child: Builder(
            builder: (context) {
              final colors = context.componentColors;
              return MenuComponent(
                title: 'Delete account',
                subtitle: 'Warning color title and icon',
                leading: _CatalogHugeIcon(
                  HugeIcons.strokeRoundedDelete02,
                  color: colors.warning,
                  size: IconSizes.small,
                ),
                trailing: const _CatalogTrailingIcon(
                  HugeIcons.strokeRoundedArrowRight01,
                ),
                titleColor: colors.warning,
                onTap: () {},
              );
            },
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Long text',
          child: MenuComponent(
            title:
                'Camera uploads from this device and shared albums waiting for review',
            subtitle:
                'This subtitle remains one line and truncates like Photos and Locker menu rows',
            leading: _CatalogHugeIcon(HugeIcons.strokeRoundedImageUpload),
            trailing: _CatalogTrailingIcon(HugeIcons.strokeRoundedArrowRight01),
            onTap: _completeAfterDelay,
          ),
        ),
      ],
    );
  }

  void _setToggleSelected(bool value) {
    setState(() => _toggleSelected = value);
  }
}

Future<void> _completeAfterDelay() {
  return Future<void>.delayed(const Duration(milliseconds: 650));
}

Future<void> _completeSlowly() {
  return Future<void>.delayed(const Duration(milliseconds: 900));
}

Future<void> _completeQuickly() {
  return Future<void>.delayed(const Duration(milliseconds: 120));
}

Future<void> _failAfterDelay(BuildContext context) async {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Something went wrong')));
  }
  throw StateError('Preview action failed');
}

class _MenuItemInteractionStatesPreview extends StatelessWidget {
  const _MenuItemInteractionStatesPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MenuComponent(
          title: 'Open storage plan',
          subtitle: 'Tap only, no execution UI',
          leading: const _CatalogHugeIcon(HugeIcons.strokeRoundedDatabase),
          trailing: const _CatalogTrailingIcon(
            HugeIcons.strokeRoundedArrowRight01,
          ),
          shouldSurfaceExecutionStates: false,
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Opened')));
          },
        ),
        const SizedBox(height: Spacing.md),
        const MenuComponent(
          title: 'Updating backup',
          subtitle: 'Execution loading, then success',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedCloudUpload),
          trailing: _CatalogTrailingIcon(HugeIcons.strokeRoundedArrowRight01),
          shouldSurfaceExecutionStates: true,
          onTap: _completeSlowly,
        ),
        const SizedBox(height: Spacing.md),
        const MenuComponent(
          title: 'Copied recovery key',
          subtitle: 'Fast success confirmation',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedCopy01),
          trailing: _CatalogTrailingIcon(HugeIcons.strokeRoundedArrowRight01),
          shouldSurfaceExecutionStates: true,
          shouldShowSuccessConfirmation: true,
          onTap: _completeQuickly,
        ),
        const SizedBox(height: Spacing.md),
        MenuComponent(
          title: 'Sync backup',
          subtitle: 'Error resets to idle',
          leading: const _CatalogHugeIcon(HugeIcons.strokeRoundedRefresh),
          trailing: const _CatalogTrailingIcon(
            HugeIcons.strokeRoundedArrowRight01,
          ),
          titleColor: context.componentColors.warning,
          iconColor: context.componentColors.warning,
          shouldSurfaceExecutionStates: true,
          onTap: () => _failAfterDelay(context),
        ),
        const SizedBox(height: Spacing.md),
        const MenuComponent(
          title: 'Opening sessions',
          subtitle: 'Loading only, no success tick',
          leading: _CatalogHugeIcon(HugeIcons.strokeRoundedUserGroup),
          trailing: _CatalogTrailingIcon(HugeIcons.strokeRoundedArrowRight01),
          showOnlyLoadingState: true,
          onTap: _completeSlowly,
        ),
      ],
    );
  }
}

class _MenuItemMatrix extends StatelessWidget {
  const _MenuItemMatrix({
    required this.toggleSelected,
    required this.onToggleChanged,
    this.selected = false,
  });

  final bool toggleSelected;
  final ValueChanged<bool> onToggleChanged;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final trailingKinds = selected
        ? const [_MenuItemTrailingKind.icon, _MenuItemTrailingKind.none]
        : _MenuItemTrailingKind.values;
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.md,
      children: [
        for (final hasSubtitle in const [true, false])
          for (final hasLeading in const [true, false])
            for (final trailingKind in trailingKinds)
              _MenuItemExample(
                selected: selected,
                hasLeading: hasLeading,
                hasSubtitle: hasSubtitle,
                trailingKind: trailingKind,
                toggleSelected: toggleSelected,
                onToggleChanged: onToggleChanged,
              ),
      ],
    );
  }
}

class _MenuItemExample extends StatelessWidget {
  const _MenuItemExample({
    required this.selected,
    required this.hasLeading,
    required this.hasSubtitle,
    required this.trailingKind,
    required this.toggleSelected,
    required this.onToggleChanged,
  });

  final bool selected;
  final bool hasLeading;
  final bool hasSubtitle;
  final _MenuItemTrailingKind trailingKind;
  final bool toggleSelected;
  final ValueChanged<bool> onToggleChanged;

  @override
  Widget build(BuildContext context) {
    return MenuComponent(
      title: hasLeading ? 'Camera uploads' : 'Storage plan',
      subtitle: hasSubtitle ? '834 items' : null,
      leading: hasLeading
          ? const _CatalogHugeIcon(
              HugeIcons.strokeRoundedUser,
              size: IconSizes.small,
            )
          : null,
      trailing: _trailing(context),
      selected: selected,
      onTap: () {},
    );
  }

  Widget? _trailing(BuildContext context) {
    final colors = context.componentColors;
    if (selected) {
      return _CatalogHugeIcon(
        HugeIcons.strokeRoundedCheckmarkCircle02,
        color: colors.primary,
        size: IconSizes.small,
      );
    }
    return switch (trailingKind) {
      _MenuItemTrailingKind.icon => const _CatalogTrailingIcon(
        HugeIcons.strokeRoundedMoreVertical,
      ),
      _MenuItemTrailingKind.toggle => ToggleSwitchComponent(
        selected: toggleSelected,
        onChanged: onToggleChanged,
      ),
      _MenuItemTrailingKind.none => null,
    };
  }
}

class _BottomSheetPreview extends StatelessWidget {
  const _BottomSheetPreview();

  @override
  Widget build(BuildContext context) {
    return _CatalogPreviewList(
      children: [
        _CatalogPreviewGroup(
          title: 'Launch sheets',
          child: Column(
            children: [
              ButtonComponent(
                label: 'Open default sheet',
                onTap: () => _showDefaultSheet(context),
              ),
              const SizedBox(height: Spacing.md),
              ButtonComponent(
                label: 'Open choice sheet',
                variant: ButtonComponentVariant.secondary,
                onTap: () => _showChoiceSheet(context),
              ),
              const SizedBox(height: Spacing.md),
              ButtonComponent(
                label: 'Open warning sheet',
                variant: ButtonComponentVariant.neutral,
                onTap: () => _showWarningSheet(context),
              ),
              const SizedBox(height: Spacing.md),
              ButtonComponent(
                label: 'Open custom content sheet',
                variant: ButtonComponentVariant.neutral,
                onTap: () => _showCustomSheet(context),
              ),
              const SizedBox(height: Spacing.md),
              ButtonComponent(
                label: 'Open generic error sheet',
                variant: ButtonComponentVariant.critical,
                onTap: () => _showErrorSheet(context),
              ),
            ],
          ),
        ),
        const _CatalogPreviewGroup(
          title: 'Default sheet',
          child: _InlineSheetFrame(child: _DefaultBottomSheetContent()),
        ),
        const _CatalogPreviewGroup(
          title: 'Choice sheet',
          child: _InlineSheetFrame(child: _ChoiceBottomSheetContent()),
        ),
        const _CatalogPreviewGroup(
          title: 'Warning sheet',
          child: _InlineSheetFrame(child: _WarningBottomSheetContent()),
        ),
        const _CatalogPreviewGroup(
          title: 'Error sheet',
          child: _InlineSheetFrame(child: _ErrorBottomSheetContent()),
        ),
        const _CatalogPreviewGroup(
          title: 'Custom content',
          child: _InlineSheetFrame(child: _CustomBottomSheetContent()),
        ),
      ],
    );
  }

  Future<void> _showDefaultSheet(BuildContext context) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => const _DefaultBottomSheetContent(),
    );
  }

  Future<void> _showChoiceSheet(BuildContext context) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => const _ChoiceBottomSheetContent(),
    );
  }

  Future<void> _showWarningSheet(BuildContext context) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => const _WarningBottomSheetContent(),
    );
  }

  Future<void> _showCustomSheet(BuildContext context) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (_) => const _CustomBottomSheetContent(),
    );
  }

  Future<void> _showErrorSheet(BuildContext context) async {
    await showErrorBottomSheetComponent<void>(
      context: context,
      message:
          'It looks like something went wrong. Please retry after some time.',
      illustration: const _WarningIllustration(),
      actionLabel: 'Contact support',
      onActionTap: () async {
        await Navigator.of(context).maybePop();
      },
    );
  }
}

class _DefaultBottomSheetContent extends StatelessWidget {
  const _DefaultBottomSheetContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: 'Title',
      content: Text(
        'Imagine a scenario where a message has been sent, a bridge of trust '
        'is being built, yet the other side remains silent.',
        style: TextStyles.body.copyWith(color: colors.textLight),
      ),
      actions: [
        ButtonComponent(
          label: 'Button',
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
        ButtonComponent(
          label: 'Button',
          variant: ButtonComponentVariant.secondary,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _ChoiceBottomSheetContent extends StatelessWidget {
  const _ChoiceBottomSheetContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: 'Delete link?',
      content: Text(
        'This action removes access for anyone who has the shared link.',
        style: TextStyles.body.copyWith(color: colors.textLight),
      ),
      actions: [
        ButtonComponent(
          label: 'Delete link',
          variant: ButtonComponentVariant.critical,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
        ButtonComponent(
          label: 'Cancel',
          variant: ButtonComponentVariant.secondary,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _WarningBottomSheetContent extends StatelessWidget {
  const _WarningBottomSheetContent();

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: 'Title',
      message:
          'Imagine a scenario where a message has been sent, a bridge of trust '
          'is being built, yet the other side remains silent.',
      illustration: const _WarningIllustration(),
      actions: [
        ButtonComponent(
          label: 'Button',
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
        ButtonComponent(
          label: 'Button',
          variant: ButtonComponentVariant.secondary,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _ErrorBottomSheetContent extends StatelessWidget {
  const _ErrorBottomSheetContent();

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: 'Error',
      message:
          'It looks like something went wrong. Please retry after some time.',
      illustration: const _WarningIllustration(),
      actions: [
        ButtonComponent(
          label: 'Contact support',
          variant: ButtonComponentVariant.secondary,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _CustomBottomSheetContent extends StatelessWidget {
  const _CustomBottomSheetContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: 'Share link',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Anyone with this link can view the shared item.',
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.md,
              48,
              Spacing.md,
            ),
            decoration: BoxDecoration(
              color: colors.fillDark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Text(
                  'https://ente.io/share/example-link',
                  style: TextStyles.body.copyWith(color: colors.textBase),
                ),
                Positioned(
                  right: -44,
                  top: -8,
                  child: IconButtonComponent(
                    tooltip: 'Copy link',
                    variant: IconButtonComponentVariant.unfilled,
                    icon: const _CatalogHugeIcon(HugeIcons.strokeRoundedCopy01),
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ButtonComponent(
          label: 'Share link',
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
        ButtonComponent(
          label: 'Delete link',
          variant: ButtonComponentVariant.tertiaryCritical,
          onTap: () async {
            await Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _InlineSheetFrame extends StatelessWidget {
  const _InlineSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 375),
      child: child,
    );
  }
}

class _WarningIllustration extends StatelessWidget {
  const _WarningIllustration();

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/warning-grey.png', width: 101, height: 89);
  }
}
