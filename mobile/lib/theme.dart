import 'package:flutter/material.dart';

/// Shared visual tokens mirrored from the macOS and Windows HUD.
class HudColors {
  const HudColors._();

  static const background = Color(0xFF0B1120);
  static const window = Color(0xFF101722);
  static const surface = Color(0xFF151E2B);
  static const surfaceRaised = Color(0xFF1B2533);
  static const surfaceHover = Color(0xFF223041);
  static const controlFill = Color(0x14FFFFFF);
  static const controlHover = Color(0x24FFFFFF);
  static const border = Color(0x2EFFFFFF);
  static const borderStrong = Color(0x4DFFFFFF);
  static const divider = Color(0x1FFFFFFF);

  static const textPrimary = Color(0xFFF7FAFF);
  static const textSecondary = Color(0xFFD2DBE7);
  static const textTertiary = Color(0xFF99A6B8);

  static const working = Color(0xFF54ADFF);
  static const waiting = Color(0xFFFFC733);
  static const completed = Color(0xFF45E694);
  static const failed = Color(0xFFFF5E75);
  static const codex = Color(0xFF54ADFF);
  static const claude = Color(0xFFFF8C47);
  static const pi = Color(0xFF7AE35C);
  static const important = Color(0xFFFFC233);

  static Color status(String value) {
    switch (value) {
      case 'Starting':
      case 'Working':
        return working;
      case 'WaitingUser':
        return waiting;
      case 'Completed':
        return completed;
      case 'Failed':
        return failed;
      case 'Idle':
        return textSecondary;
      default:
        return textTertiary;
    }
  }

  static Color provider(String value) {
    switch (value) {
      case 'Codex':
        return codex;
      case 'Claude':
        return claude;
      case 'Pi':
        return pi;
      default:
        return textTertiary;
    }
  }

  static bool isActive(String status) =>
      status == 'Starting' || status == 'Working' || status == 'WaitingUser';
}

class HudRadii {
  const HudRadii._();

  static const double micro = 5;
  static const double control = 7;
  static const double card = 10;
  static const double panel = 14;
  static const double hero = 16;
}

class HudSpacing {
  const HudSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
}

class HudMotion {
  const HudMotion._();

  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const entrance = Duration(milliseconds: 420);
  static const pulse = Duration(milliseconds: 1600);

  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);
  static const Curve easeIn = Cubic(0.4, 0, 0.9, 0.45);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

class HudText {
  const HudText._();

  static const display = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.22,
    letterSpacing: -0.2,
    color: HudColors.textPrimary,
  );
  static const title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: HudColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 13.5,
    height: 1.5,
    color: HudColors.textPrimary,
  );
  static const bodySecondary = TextStyle(
    fontSize: 13,
    height: 1.5,
    color: HudColors.textSecondary,
  );
  static const label = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: HudColors.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 11.5,
    height: 1.4,
    color: HudColors.textTertiary,
  );
  static const micro = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: HudColors.textTertiary,
  );
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11.5,
    height: 1.4,
    color: HudColors.textSecondary,
  );
}

ThemeData buildHudTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HudColors.working,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HudColors.working,
    onPrimary: const Color(0xFF04121F),
    secondary: HudColors.completed,
    onSecondary: const Color(0xFF04140C),
    surface: HudColors.window,
    onSurface: HudColors.textPrimary,
    surfaceContainerHighest: HudColors.surfaceRaised,
    outline: HudColors.border,
    error: HudColors.failed,
    onError: const Color(0xFF2A0509),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: HudColors.background,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: HudPageTransitionsBuilder(),
        TargetPlatform.iOS: HudPageTransitionsBuilder(),
        TargetPlatform.macOS: HudPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: HudColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: HudColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: HudColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: HudColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.hero),
        side: const BorderSide(color: HudColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: HudColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HudColors.surface,
      hintStyle: HudText.caption,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: HudSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HudRadii.control),
        borderSide: const BorderSide(color: HudColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HudRadii.control),
        borderSide: const BorderSide(color: HudColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(HudRadii.control),
        borderSide: const BorderSide(color: HudColors.working, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HudColors.working,
        foregroundColor: const Color(0xFF04121F),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HudRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HudColors.working,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: HudColors.working,
      foregroundColor: const Color(0xFF04121F),
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.hero),
      ),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: HudColors.working,
      unselectedLabelColor: HudColors.textTertiary,
      indicatorColor: HudColors.working,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 14),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HudColors.working,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: HudColors.surfaceRaised,
      contentTextStyle: HudText.body,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.control),
      ),
    ),
  );
}

/// Fade + short rise used for route changes.
class HudPageTransitionsBuilder extends PageTransitionsBuilder {
  const HudPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || HudMotion.reduced(context)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: HudMotion.easeOut,
      reverseCurve: HudMotion.easeIn,
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(curved);
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.85, curve: HudMotion.easeOut),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

/// Fade + rise for content that appears on first mount.
class HudEntrance extends StatelessWidget {
  const HudEntrance({
    super.key,
    required this.child,
    this.offset = const Offset(0, 0.03),
    this.duration = HudMotion.entrance,
  });

  final Widget child;
  final Offset offset;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (HudMotion.reduced(context)) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: HudMotion.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offset.dy * (1 - value) * 400),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
