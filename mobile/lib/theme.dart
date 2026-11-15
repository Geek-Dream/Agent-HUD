import 'package:flutter/material.dart';

/// Shared visual tokens mirrored from the macOS and Windows HUD.
///
/// The mobile shell uses a restrained "dark workstation" palette: near-black
/// neutral surfaces, one hairline border, and colour reserved for status,
/// provider identity, and primary actions.
class HudColors {
  const HudColors._();

  static const background = Color(0xFF08090C);
  static const window = Color(0xFF0C0E12);
  static const surface = Color(0xFF14171D);
  static const surfaceRaised = Color(0xFF1B1F27);
  static const surfaceHover = Color(0xFF262B35);
  static const controlFill = Color(0x0FFFFFFF);
  static const controlHover = Color(0x21FFFFFF);
  static const border = Color(0x14FFFFFF);
  static const borderStrong = Color(0x30FFFFFF);
  static const divider = Color(0x12FFFFFF);

  static const textPrimary = Color(0xFFF7F9FD);
  static const textSecondary = Color(0xFFB6BECB);
  static const textTertiary = Color(0xFF7B8492);

  static const working = Color(0xFF5E9BFF);
  static const waiting = Color(0xFFF0C462);
  static const completed = Color(0xFF4FD1A0);
  static const failed = Color(0xFFFF6B7F);
  static const codex = Color(0xFF74A9FF);
  static const claude = Color(0xFFFF9A62);
  static const pi = Color(0xFF86D96E);
  static const opencode = Color(0xFF4FD6CA);
  static const important = Color(0xFFF0C462);
  static const todo = Color(0xFFB49BFF);

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
      case 'OpenCode':
        return opencode;
      default:
        return textTertiary;
    }
  }

  static bool isActive(String status) =>
      status == 'Starting' || status == 'Working' || status == 'WaitingUser';
}

class HudRadii {
  const HudRadii._();

  static const double micro = 6;
  static const double control = 10;
  static const double card = 12;
  static const double panel = 16;
  static const double hero = 20;
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

/// ---------------------------------------------------------------------------
/// Surface elevation / shadow tokens – pressed → raised → floating
/// ---------------------------------------------------------------------------
class HudElevation {
  const HudElevation._();

  static const List<BoxShadow> none = <BoxShadow>[];

  static List<BoxShadow> pressed(Color base) => <BoxShadow>[
        BoxShadow(
          color: base.withValues(alpha: 0.06),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> card(Color base) => <BoxShadow>[
        BoxShadow(
          color: base.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> floating(Color base) => <BoxShadow>[
        BoxShadow(
          color: base.withValues(alpha: 0.34),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  static List<BoxShadow> glow(Color color) => <BoxShadow>[
        BoxShadow(
          color: color.withValues(alpha: 0.16),
          blurRadius: 16,
          spreadRadius: 1,
        ),
      ];
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
    fontSize: 25,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
    color: HudColors.textPrimary,
  );
  static const title = TextStyle(
    fontSize: 16.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.15,
    color: HudColors.textPrimary,
  );
  static const body = TextStyle(
    fontSize: 14,
    height: 1.55,
    color: HudColors.textPrimary,
  );
  static const bodySecondary = TextStyle(
    fontSize: 13.5,
    height: 1.5,
    color: HudColors.textSecondary,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: HudColors.textSecondary,
  );
  static const caption = TextStyle(
    fontSize: 12,
    height: 1.45,
    color: HudColors.textTertiary,
  );
  static const micro = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: HudColors.textTertiary,
  );
  /// Small uppercase-ish label that introduces a group of content.
  static const overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.8,
    color: HudColors.textTertiary,
  );
  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
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
    outlineVariant: HudColors.divider,
    error: HudColors.failed,
    onError: const Color(0xFF2A0509),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: HudColors.background,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: HudPageTransitionsBuilder(),
        TargetPlatform.iOS: HudPageTransitionsBuilder(),
        TargetPlatform.macOS: HudPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: HudColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: HudSpacing.xl,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: HudColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: HudColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.panel),
        side: const BorderSide(color: HudColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: HudColors.divider,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: HudColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.panel),
        side: const BorderSide(color: HudColors.border),
      ),
      titleTextStyle: HudText.title.copyWith(fontSize: 18),
      contentTextStyle: HudText.bodySecondary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HudColors.controlFill,
      hintStyle: HudText.caption,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: HudSpacing.lg,
        vertical: 14,
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
        borderSide: const BorderSide(color: HudColors.working, width: 1.3),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HudColors.textPrimary,
        foregroundColor: HudColors.background,
        disabledBackgroundColor: HudColors.controlFill,
        disabledForegroundColor: HudColors.textTertiary,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HudRadii.control),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HudColors.textPrimary,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: HudColors.textSecondary,
        highlightColor: HudColors.controlFill,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: HudColors.textPrimary,
      foregroundColor: HudColors.background,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HudRadii.control),
      ),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: HudColors.textPrimary,
      unselectedLabelColor: HudColors.textTertiary,
      indicatorColor: HudColors.textPrimary,
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
        side: const BorderSide(color: HudColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: HudColors.textSecondary,
      textColor: HudColors.textPrimary,
    ),
  );
}

/// ---------------------------------------------------------------------------
/// Page background – near-black vertical wash with one very soft top glow.
/// ---------------------------------------------------------------------------
class HudScaffoldBackground extends StatelessWidget {
  const HudScaffoldBackground({
    super.key,
    required this.child,
    this.accent,
    this.scrollable = false,
  });

  final Widget child;

  /// Optional status colour that tints the top spotlight, so each screen keeps
  /// the same structure while the accent follows the current context.
  final Color? accent;

  /// When true the spotlight scrolls with the content instead of staying
  /// pinned, which avoids a visible seam on long scroll views.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final Color glow = accent ?? HudColors.working;
    final Widget layers = Stack(
      children: [
        Positioned(
          top: -180,
          left: -60,
          right: -60,
          height: 380,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    glow.withValues(alpha: 0.10),
                    glow.withValues(alpha: 0),
                  ],
                  stops: const [0, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.012),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.4],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [HudColors.window, HudColors.background],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.6],
        ),
      ),
      child: scrollable ? layers : ClipRect(child: layers),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Standard surface card: vertical gradient fill, hairline ring, inner top
/// highlight, and an optional accent hairline. Elevation comes from contrast,
/// not from drop shadows, which keeps the mobile UI crisp on dark OLED screens.
/// ---------------------------------------------------------------------------
class HudSurfaceCard extends StatelessWidget {
  const HudSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HudSpacing.xl),
    this.margin,
    this.radius = HudRadii.panel,
    this.color = HudColors.surface,
    this.borderColor = HudColors.border,
    this.onTap,
    this.shadows,
    this.accent,
    this.highlight = true,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadows;

  /// Optional left-edge status hairline, e.g. for a working session.
  final Color? accent;

  /// Whether to paint the 1px inner highlight along the top edge.
  final bool highlight;

  /// Overrides the default [color] gradient.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final Gradient fill = gradient ??
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(HudColors.controlFill, color),
            color,
          ],
        );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: fill,
            borderRadius: borderRadius,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Stack(
            children: [
              if (highlight)
                Positioned(
                  top: 0,
                  left: radius * 0.9,
                  right: radius * 0.9,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              if (accent != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent!.withValues(alpha: 0.9),
                            accent!.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              onTap == null
                  ? Padding(padding: padding, child: child)
                  : InkWell(
                      onTap: onTap,
                      highlightColor:
                          HudColors.controlHover.withValues(alpha: 0.25),
                      splashColor: HudColors.controlFill.withValues(alpha: 0.4),
                      child: Padding(padding: padding, child: child),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny neutral badge used for counts and secondary tags.
class HudCountBadge extends StatelessWidget {
  const HudCountBadge({
    super.key,
    required this.value,
    this.color = HudColors.textTertiary,
  });

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: HudColors.controlFill,
        borderRadius: BorderRadius.circular(HudRadii.micro),
      ),
      child: Text(
        value,
        style: HudText.micro.copyWith(
          fontSize: 10,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Right-to-left page push with a soft fade, used for session details.
class HudSlidePageRoute<T> extends PageRouteBuilder<T> {
  HudSlidePageRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (HudMotion.reduced(context)) return child;
            final Animation<double> curved = CurvedAnimation(
              parent: animation,
              curve: HudMotion.easeOut,
              reverseCurve: HudMotion.easeIn,
            );
            final Animation<Offset> slide = Tween<Offset>(
              begin: const Offset(0.16, 0),
              end: Offset.zero,
            ).animate(curved);
            final Animation<double> fade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.72, curve: Curves.easeOut),
            );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(position: slide, child: child),
            );
          },
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
      begin: const Offset(0, 0.02),
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
