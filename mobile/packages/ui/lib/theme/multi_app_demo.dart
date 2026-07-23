// Demo: Complete working example showing multi-app theme compatibility
// This file demonstrates how the reusable theme system works for different apps

import 'package:ente_ui/theme/colors.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:ente_ui/theme/ente_theme_data.dart';
import 'package:flutter/material.dart';

/// App 1: E-commerce app with blue theme
class ECommerceApp {
  static const Color brandBlue = Color(0xFF1976D2);

  static final schemes = ColorSchemeBuilder.fromPrimaryColor(brandBlue);

  static final lightTheme = createAppThemeData(
    brightness: Brightness.light,
    colorScheme: schemes.light,
  );

  static final darkTheme = createAppThemeData(
    brightness: Brightness.dark,
    colorScheme: schemes.dark,
  );
}

/// App 2: Social media app with purple theme
class SocialMediaApp {
  static const Color brandPurple = Color(0xFF9C27B0);

  static final schemes = ColorSchemeBuilder.fromPrimaryColor(brandPurple);

  static final lightTheme = createAppThemeData(
    brightness: Brightness.light,
    colorScheme: schemes.light,
  );

  static final darkTheme = createAppThemeData(
    brightness: Brightness.dark,
    colorScheme: schemes.dark,
  );
}

/// App 3: Finance app with green theme
class FinanceApp {
  static final schemes = ColorSchemeBuilder.fromCustomColors(
    primary700: const Color(0xFF388E3C),
    primary500: const Color(0xFF4CAF50),
    primary400: const Color(0xFF66BB6A),
    primary300: const Color(0xFF81C784),
    gradientButtonBgColors: const [
      Color(0xFF388E3C),
      Color(0xFF4CAF50),
      Color(0xFF66BB6A),
    ],
  );

  static final lightTheme = createAppThemeData(
    brightness: Brightness.light,
    colorScheme: schemes.light,
  );

  static final darkTheme = createAppThemeData(
    brightness: Brightness.dark,
    colorScheme: schemes.dark,
  );
}

/// App 4: Gaming app with orange theme
class GamingApp {
  static final customLightScheme = EnteColorScheme.light(
    primary700: const Color(0xFFE65100),
    primary500: const Color(0xFFFF9800),
    primary400: const Color(0xFFFFB74D),
    primary300: const Color(0xFFFFCC02),
    iconButtonColor: const Color(0xFFFF6F00),
    gradientButtonBgColors: const [
      Color(0xFFE65100),
      Color(0xFFFF9800),
      Color(0xFFFFB74D),
    ],
    warning500: const Color(0xFFF44336), // Custom warning for gaming
  );

  static final customDarkScheme = EnteColorScheme.dark(
    primary700: const Color(0xFFE65100),
    primary500: const Color(0xFFFF9800),
    primary400: const Color(0xFFFFB74D),
    primary300: const Color(0xFFFFCC02),
    iconButtonColor: const Color(0xFFFF6F00),
    gradientButtonBgColors: const [
      Color(0xFFE65100),
      Color(0xFFFF9800),
      Color(0xFFFFB74D),
    ],
    warning500: const Color(0xFFF44336),
  );

  static final lightTheme = createAppThemeData(
    brightness: Brightness.light,
    colorScheme: customLightScheme,
  );

  static final darkTheme = createAppThemeData(
    brightness: Brightness.dark,
    colorScheme: customDarkScheme,
  );
}

/// Demo widget that shows how UI components adapt to different app themes
class MultiAppThemeDemo extends StatefulWidget {
  const MultiAppThemeDemo({super.key});

  @override
  State<MultiAppThemeDemo> createState() => _MultiAppThemeDemoState();
}

class _MultiAppThemeDemoState extends State<MultiAppThemeDemo> {
  int currentAppIndex = 0;
  bool isDarkMode = false;

  final List<({String name, ThemeData light, ThemeData dark})> apps = [
    (
      name: "E-commerce",
      light: ECommerceApp.lightTheme,
      dark: ECommerceApp.darkTheme,
    ),
    (
      name: "Social Media",
      light: SocialMediaApp.lightTheme,
      dark: SocialMediaApp.darkTheme,
    ),
    (name: "Finance", light: FinanceApp.lightTheme, dark: FinanceApp.darkTheme),
    (name: "Gaming", light: GamingApp.lightTheme, dark: GamingApp.darkTheme),
  ];

  @override
  Widget build(BuildContext context) {
    final currentApp = apps[currentAppIndex];
    final currentTheme = isDarkMode ? currentApp.dark : currentApp.light;

    return MaterialApp(
      title: '${currentApp.name} App Demo',
      theme: currentTheme,
      home: DemoHomePage(
        appName: currentApp.name,
        onAppChanged: (index) => setState(() => currentAppIndex = index),
        onThemeChanged: (dark) => setState(() => isDarkMode = dark),
        currentAppIndex: currentAppIndex,
        isDarkMode: isDarkMode,
        appCount: apps.length,
      ),
    );
  }
}

class DemoHomePage extends StatelessWidget {
  final String appName;
  final Function(int) onAppChanged;
  final Function(bool) onThemeChanged;
  final int currentAppIndex;
  final bool isDarkMode;
  final int appCount;

  const DemoHomePage({
    super.key,
    required this.appName,
    required this.onAppChanged,
    required this.onThemeChanged,
    required this.currentAppIndex,
    required this.isDarkMode,
    required this.appCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundBase,
      appBar: AppBar(
        title: Text('$appName Theme Demo'),
        backgroundColor: colorScheme.backgroundElevated,
        foregroundColor: colorScheme.textBase,
        actions: [
          Switch(
            value: isDarkMode,
            onChanged: onThemeChanged,
            activeThumbColor: colorScheme.primary500,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Selector
            Text(
              'Switch App Theme:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.textBase,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: List.generate(appCount, (index) {
                final isSelected = index == currentAppIndex;
                return FilterChip(
                  label: Text(
                    ['E-commerce', 'Social', 'Finance', 'Gaming'][index],
                  ),
                  selected: isSelected,
                  onSelected: (_) => onAppChanged(index),
                  backgroundColor: colorScheme.fillFaint,
                  selectedColor: colorScheme.primary400,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? colorScheme.backgroundBase
                        : colorScheme.textBase,
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            // UI Components Demo
            Text(
              'UI Components:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.textBase,
              ),
            ),
            const SizedBox(height: 16),

            // Background colors demo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.backgroundElevated,
                border: Border.all(color: colorScheme.strokeFaint),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Card with elevated background',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.textBase,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This is secondary text that adapts to the theme.',
                    style: TextStyle(color: colorScheme.textMuted),
                  ),
                  Text(
                    'This is faint text for hints and labels.',
                    style: TextStyle(color: colorScheme.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Buttons demo
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary500,
                      foregroundColor: colorScheme.backgroundBase,
                    ),
                    onPressed: () {},
                    child: const Text('Primary Button'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: colorScheme.fillFaint,
                      foregroundColor: colorScheme.textBase,
                      side: BorderSide(color: colorScheme.strokeMuted),
                    ),
                    onPressed: () {},
                    child: const Text('Secondary'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Gradient button demo
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: colorScheme.gradientButtonBgColors,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Gradient Button',
                  style: TextStyle(
                    color: colorScheme.backgroundBase,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Warning demo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.warning500.withValues(alpha: 0.1),
                border: Border.all(color: colorScheme.warning500),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: colorScheme.warning500, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Warning message with custom warning color',
                      style: TextStyle(color: colorScheme.warning700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Color palette display
            Text(
              'Color Palette:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.textBase,
              ),
            ),
            const SizedBox(height: 16),
            _buildColorPalette(colorScheme),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colorScheme.iconButtonColor,
        foregroundColor: colorScheme.backgroundBase,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$appName theme is working!'),
              backgroundColor: colorScheme.primary500,
            ),
          );
        },
        child: const Icon(Icons.palette),
      ),
    );
  }

  Widget _buildColorPalette(EnteColorScheme colorScheme) {
    final colors = [
      ('Primary 700', colorScheme.primary700),
      ('Primary 500', colorScheme.primary500),
      ('Primary 400', colorScheme.primary400),
      ('Primary 300', colorScheme.primary300),
      ('Warning', colorScheme.warning500),
      ('Icon Button', colorScheme.iconButtonColor),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors.map((color) {
        return Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.$2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.strokeFaint),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              color.$1,
              style: TextStyle(fontSize: 10, color: colorScheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        );
      }).toList(),
    );
  }
}

// Example of how to use this in main.dart:
void main() {
  runApp(const MultiAppThemeDemo());
}
