import "dart:async";
import "dart:io";

import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/update_service.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/settings/pages/about_page.dart";
import "package:locker/ui/settings/pages/account_settings_page.dart";
import "package:locker/ui/settings/pages/general_settings_page.dart";
import "package:locker/ui/settings/pages/security_settings_page.dart";
import "package:locker/ui/settings/pages/support_page.dart";
import "package:locker/ui/settings/pages/theme_settings_page.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;
  String _searchQuery = "";
  List<_SearchResultEntry> _searchResults = [];
  late List<_SearchableSetting> _allSettings;
  late List<_SearchableSetting> _suggestions;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _allSettings = _buildSettingsList(context);
    _suggestions = _getDefaultSuggestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  List<_SearchableSetting> _buildSettingsList(BuildContext context) {
    final l10n = context.l10n;
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();

    return [
      if (hasLoggedIn) ...[
        _SearchableSetting(
          title: l10n.account,
          category: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          page: const AccountSettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.changeEmail,
          category: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          page: const AccountSettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.recoveryKey,
          category: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          page: const AccountSettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.changePassword,
          category: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          page: const AccountSettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.deleteAccount,
          category: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          page: const AccountSettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.security,
          category: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          page: const SecuritySettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.emailVerificationToggle,
          category: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          page: const SecuritySettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.passkey,
          category: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          page: const SecuritySettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.appLock,
          category: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          page: const SecuritySettingsPage(),
        ),
        _SearchableSetting(
          title: l10n.viewActiveSessions,
          category: l10n.security,
          icon: HugeIcons.strokeRoundedSecurityCheck,
          page: const SecuritySettingsPage(),
        ),
        if (Platform.isAndroid || kDebugMode)
          _SearchableSetting(
            title: l10n.appearance,
            category: l10n.appearance,
            icon: HugeIcons.strokeRoundedSun03,
            page: const ThemeSettingsPage(),
          ),
      ],
      _SearchableSetting(
        title: l10n.general,
        category: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        page: const GeneralSettingsPage(),
      ),
      _SearchableSetting(
        title: l10n.selectLanguage,
        category: l10n.general,
        icon: HugeIcons.strokeRoundedSettings01,
        page: const GeneralSettingsPage(),
      ),
      _SearchableSetting(
        title: l10n.helpAndSupport,
        category: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        page: const SupportPage(),
      ),
      _SearchableSetting(
        title: l10n.askAQuestion,
        category: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        page: const SupportPage(),
      ),
      _SearchableSetting(
        title: l10n.requestAFeature,
        category: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        page: const SupportPage(),
      ),
      _SearchableSetting(
        title: l10n.reportAnIssue,
        category: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        page: const SupportPage(),
      ),
      _SearchableSetting(
        title: l10n.about,
        category: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        page: const AboutPage(),
      ),
      _SearchableSetting(
        title: l10n.weAreOpenSource,
        category: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        page: const AboutPage(),
      ),
      _SearchableSetting(
        title: l10n.blog,
        category: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        page: const AboutPage(),
      ),
      _SearchableSetting(
        title: l10n.privacy,
        category: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        page: const AboutPage(),
      ),
      _SearchableSetting(
        title: l10n.termsOfServicesTitle,
        category: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        page: const AboutPage(),
      ),
      if (UpdateService.instance.isIndependent())
        _SearchableSetting(
          title: l10n.checkForUpdates,
          category: l10n.about,
          icon: HugeIcons.strokeRoundedInformationCircle,
          page: const AboutPage(),
        ),
      if (hasLoggedIn)
        _SearchableSetting(
          title: l10n.logout,
          category: l10n.logout,
          icon: HugeIcons.strokeRoundedLogout05,
          onTap: _onLogoutTapped,
        ),
    ];
  }

  List<_SearchableSetting> _getDefaultSuggestions() {
    final l10n = context.l10n;
    final hasLoggedIn = Configuration.instance.hasConfiguredAccount();

    return _allSettings.where((s) {
      if (hasLoggedIn) {
        return s.title == l10n.appLock ||
            s.title == l10n.appearance ||
            s.title == l10n.selectLanguage ||
            s.title == l10n.privacy;
      } else {
        return s.title == l10n.selectLanguage ||
            s.title == l10n.help ||
            s.title == l10n.privacy;
      }
    }).toList();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query.trim().toLowerCase();
          if (_searchQuery.isEmpty) {
            _searchResults = [];
          } else {
            _searchResults = _allSettings
                .asMap()
                .entries
                .where((entry) {
                  final setting = entry.value;
                  return _containsQuery(setting.title, _searchQuery) ||
                      _containsQuery(setting.category, _searchQuery);
                })
                .map(
                  (entry) => _SearchResultEntry(
                    setting: entry.value,
                    category: entry.value.category,
                  ),
                )
                .toList();
          }
        });
      }
    });
  }

  bool _containsQuery(String text, String query) {
    if (text.isEmpty) return false;
    final lowerText = text.toLowerCase();
    if (lowerText.contains(query)) {
      return true;
    }
    final words = lowerText.split(RegExp(r'[\s\-_\.]+'));
    return words.any((word) => word.startsWith(query));
  }

  Future<void> _onSettingTapped(_SearchableSetting setting) async {
    if (setting.onTap != null) {
      await setting.onTap!();
    } else if (setting.page != null) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => setting.page!));
    }
  }

  Future<void> _onLogoutTapped() async {
    await _confirmLogout();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: context.l10n.warning,
        message: context.l10n.areYouSureYouWantToLogout,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.yesLogout,
            variant: ButtonComponentVariant.critical,
            shouldSurfaceExecutionStates: false,
            onTap: () {
              Navigator.of(sheetContext).pop(true);
            },
          ),
        ],
      ),
    );
    if (shouldLogout == true && mounted) {
      await UserService.instance.logout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            Expanded(
              child: _searchQuery.isEmpty
                  ? _buildSuggestions()
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextInputComponent(
        controller: _searchController,
        focusNode: _focusNode,
        hintText: context.l10n.searchSettings,
        onChanged: _onSearchChanged,
        prefix: HugeIcon(
          icon: HugeIcons.strokeRoundedSearch01,
          size: 20,
          color: colors.textLight,
          strokeWidth: 1.6,
        ),
        suffix: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _searchController.text.isNotEmpty
              ? _clearSearch
              : () => Navigator.of(context).pop(),
          child: SizedBox.square(
            dimension: 24,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: 18,
              color: colors.textLight,
              strokeWidth: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = "";
      _searchResults = [];
    });
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(context.l10n.suggestions, style: TextStyles.large),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (setting) => FilterChipComponent(
                    label: setting.title,
                    onChanged: (_) => _onSettingTapped(setting),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.noResultsFound,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
        ),
      );
    }

    final rows = _buildResultRows();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        return rows[index];
      },
    );
  }

  List<Widget> _buildResultRows() {
    final categoryCounts = <String, int>{};
    for (final entry in _searchResults) {
      categoryCounts.update(
        entry.category,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final rows = <Widget>[];
    String? currentCategory;
    for (final entry in _searchResults) {
      final shouldShowHeader =
          categoryCounts[entry.category] != null &&
          categoryCounts[entry.category]! >= 2;
      if (shouldShowHeader && currentCategory != entry.category) {
        currentCategory = entry.category;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(entry.category, style: TextStyles.large),
          ),
        );
      }
      rows.add(_buildSearchResultItem(entry.setting));
    }
    return rows;
  }

  Widget _buildSearchResultItem(_SearchableSetting setting) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: SettingsItem(
        title: setting.title,
        subtitle: setting.title != setting.category ? setting.category : null,
        icon: setting.icon,
        showOnlyLoadingState: true,
        onTap: () => _onSettingTapped(setting),
      ),
    );
  }
}

class _SearchableSetting {
  final String title;
  final String category;
  final List<List<dynamic>>? icon;
  final Widget? page;
  final FutureOr<void> Function()? onTap;

  const _SearchableSetting({
    required this.title,
    required this.category,
    this.icon,
    this.page,
    this.onTap,
  });
}

class _SearchResultEntry {
  final _SearchableSetting setting;
  final String category;

  const _SearchResultEntry({required this.setting, required this.category});
}
