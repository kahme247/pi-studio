// Design tokens: surfaces, text ramp, accents. Extracted from main.dart.
import 'package:flutter/material.dart';

/// Accent for "this session is running", sampled from the reference UI.
///
/// That UI uses it for its live indicator and nothing else, so it is wired to
/// the same meaning here rather than promoted to the brand accent.
const liveGreen = Color(0xFF00C950);

/// Added lines and `+N` counts.
///
/// Deliberately a muted green rather than [liveGreen]: a vivid tone works as a
/// small indicator but is garish behind a wall of diff text, and the two mean
/// different things — "working" versus "added".
const diffAdded = Color(0xFF5EA86D);

/// Dark theme sampled from a reference UI rather than eyeballed.
///
/// Two near-black surfaces instead of one, a three-step text ramp, and a
/// hairline border. `#121216` and `#18191B` are uniform fills covering ~93% of
/// that screenshot, `#2F2F37` is the 1px seam between its two panes, and
/// `#B0B4BA` / `#FCFCFD` are its two text tones.
///
/// The brand accent stays magenta: the reference's chrome is entirely neutral,
/// so borrowing its greys does not mean borrowing an accent it does not have.
///
/// When [translucent] is true (Windows, where the window backdrop itself is
/// transparent) the scaffold paints nothing so the wallpaper can show
/// through wherever a pane opts into translucency — currently only the
/// sidebar. Every surface token stays fully opaque; panes choose their own
/// alpha explicitly, so text contrast never depends on the wallpaper.
ThemeData appTheme({bool translucent = false}) {
  const ink0 = Color(0xFF121216); // main pane, transcript
  const ink1 = Color(0xFF18191B); // sidebar, rail, cards, menus
  const ink2 = Color(0xFF202226); // composer, inputs, raised inside a card
  const ink3 = Color(0xFF27292C); // selected row, chips, toggles
  const ink5 = Color(0xFF8E9298); // tertiary: hints, labels, outlines
  const ink7 = Color(0xFFB0B4BA); // secondary text
  const ink9 = Color(0xFFFCFCFD); // primary text
  const magenta = Color(0xFFD4688E);
  const cyan = Color(0xFF62ADC9);
  const rule = Color(0xFF2F2F37); // hairline between surfaces

  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: magenta,
    onPrimary: ink0,
    primaryContainer: Color(0x20D4688E),
    onPrimaryContainer: ink9,
    secondary: cyan,
    onSecondary: ink0,
    secondaryContainer: Color(0x2062ADC9),
    onSecondaryContainer: ink9,
    surface: ink0,
    onSurface: ink9,
    onSurfaceVariant: ink7,
    // In the reference the sidebar is lighter than the transcript, so the
    // "lowest" token carries the higher value here. These are paint colours,
    // not a literal Material elevation ramp.
    surfaceContainerLowest: ink1,
    surfaceContainerLow: ink1,
    surfaceContainer: ink1,
    surfaceContainerHigh: ink2,
    surfaceContainerHighest: ink3,
    outline: ink5,
    outlineVariant: rule,
    // Lightened from the old #CF5668, which sat at 4.34 on a card — under the
    // 4.5 that error text needs to stay readable. Kept clearly red so it is
    // never mistaken for the magenta accent.
    error: Color(0xFFE86E70),
    onError: ink9,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Geist',
  );

  return base.copyWith(
    hintColor: ink5,
    scaffoldBackgroundColor: translucent ? Colors.transparent : ink0,
    visualDensity: VisualDensity.compact,
    // InkSparkle builds a per-tap GPU shader. That is a touch idiom: it costs
    // frames here and reads as noise under a mouse. A cheap ripple plus the
    // hover states below carry pointer feedback instead.
    splashFactory: InkRipple.splashFactory,
    // Bare InkWell (the majority of this UI) falls back to these, so one line
    // here gives every hand-rolled control a hover/focus response.
    hoverColor: ink9.withValues(alpha: 0.055),
    highlightColor: ink9.withValues(alpha: 0.04),
    focusColor: magenta.withValues(alpha: 0.16),
    dividerTheme: const DividerThemeData(color: rule, thickness: 1, space: 1),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => ink5.withValues(
          alpha: states.contains(WidgetState.hovered) ? 0.6 : 0.28,
        ),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 17.5,
        fontWeight: FontWeight.w600,
        color: ink9,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: ink9,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14.5,
        height: 1.55,
        color: ink9,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.35,
        color: ink7,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: ink9,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontSize: 12,
        color: ink5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // A step above the card it usually sits in, so the field reads as a
      // field rather than a hole.
      fillColor: ink2,
      hintStyle: const TextStyle(color: ink5, fontWeight: FontWeight.w400),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: ink1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: rule),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(ink1),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: rule),
          ),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 3500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: ink1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: rule),
      ),
      textStyle: const TextStyle(fontSize: 12.5, color: ink9),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        overlayColor: ink0.withValues(alpha: 0.14),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        overlayColor: ink9.withValues(alpha: 0.08),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(30, 30),
        iconSize: 18,
        padding: EdgeInsets.zero,
        // Without an overlay an IconButton looks inert until you press it.
        hoverColor: ink9.withValues(alpha: 0.09),
        highlightColor: ink9.withValues(alpha: 0.11),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink1,
      contentTextStyle: const TextStyle(fontSize: 13.5, color: ink9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: rule),
      ),
    ),
  );
}
