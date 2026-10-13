import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// -- Dark palette (original v1.0 look) ---------------------------------------
const Color kBackgroundColor = Color(0xFF0D0E12);
const Color kSurfaceColor = Color(0xFF161821);
const Color kSurfaceAltColor = Color(0xFF1F2230);
const Color kBorderColor = Color(0xFF2A2D3A);
const Color kAccentColor = Color(0xFF5B7CFA);
const Color kAccent2Color = Color(0xFF8A5BFA);
const Color kMutedTextColor = Color(0xFF9AA0B4);

// -- Light palette ------------------------------------------------------------
const Color kLightBackgroundColor = Color(0xFFF4F5FA);
const Color kLightSurfaceColor = Color(0xFFFFFFFF);
const Color kLightSurfaceAltColor = Color(0xFFECEEF6);
const Color kLightBorderColor = Color(0xFFD9DCE8);
const Color kLightMutedTextColor = Color(0xFF666D85);

const LinearGradient kBrandGradient = LinearGradient(
  colors: <Color>[kAccentColor, kAccent2Color],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Brightness-resolved palette so every widget can adapt to the active
/// theme without hardcoding dark colors.
class ZPalette {
  const ZPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.muted,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color muted;

  static const ZPalette dark = ZPalette(
    background: kBackgroundColor,
    surface: kSurfaceColor,
    surfaceAlt: kSurfaceAltColor,
    border: kBorderColor,
    muted: kMutedTextColor,
  );

  static const ZPalette light = ZPalette(
    background: kLightBackgroundColor,
    surface: kLightSurfaceColor,
    surfaceAlt: kLightSurfaceAltColor,
    border: kLightBorderColor,
    muted: kLightMutedTextColor,
  );
}

/// Theme-aware palette access: `context.palette.surface` etc.
extension ZPaletteX on BuildContext {
  ZPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? ZPalette.dark
      : ZPalette.light;
  Color get zBackground => palette.background;
  Color get zSurface => palette.surface;
  Color get zSurfaceAlt => palette.surfaceAlt;
  Color get zBorder => palette.border;
  Color get zMuted => palette.muted;
}

ThemeData _baseTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final ZPalette p = isDark ? ZPalette.dark : ZPalette.light;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kAccentColor,
    brightness: brightness,
    surface: p.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      // Transparent system bars with icons that contrast the app background
      // in both themes (edge-to-edge is enforced on Android 15+).
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
    dividerColor: p.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      hintStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kAccentColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surfaceAlt),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? kSurfaceAltColor : const Color(0xFF2A2D3A),
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

ThemeData buildDarkTheme() => _baseTheme(Brightness.dark);

ThemeData buildLightTheme() => _baseTheme(Brightness.light);

/// Gradient "Z" brand mark used in the app bar and empty state.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Text(
        'Z',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.6,
        ),
      ),
    );
  }
}
