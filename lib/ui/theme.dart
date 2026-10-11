import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kBackgroundColor = Color(0xFF0D0E12);
const Color kSurfaceColor = Color(0xFF161821);
const Color kSurfaceAltColor = Color(0xFF1F2230);
const Color kBorderColor = Color(0xFF2A2D3A);
const Color kAccentColor = Color(0xFF5B7CFA);
const Color kAccent2Color = Color(0xFF8A5BFA);
const Color kMutedTextColor = Color(0xFF9AA0B4);

const LinearGradient kBrandGradient = LinearGradient(
  colors: <Color>[kAccentColor, kAccent2Color],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

ThemeData buildDarkTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kAccentColor,
    brightness: Brightness.dark,
    surface: kSurfaceColor,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      // Dark app: transparent system bars + light icons so the status bar
      // clock/battery and the gesture pill stay readable without a
      // contrasting band behind them.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    ),
    dividerColor: kBorderColor,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceAltColor,
      hintStyle: const TextStyle(color: kMutedTextColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: kAccentColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(kSurfaceAltColor),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: kSurfaceAltColor,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

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
