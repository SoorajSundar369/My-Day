import 'package:flutter/material.dart';

/// Pushed pages swing in with a slight 3D rotation while the old page recedes.
class Depth3DTransitions extends PageTransitionsBuilder {
  const Depth3DTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final inCurve = CurvedAnimation(
        parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, outCurve]),
      child: child,
      builder: (context, child) {
        final t = inCurve.value;
        final o = outCurve.value;
        final width = MediaQuery.sizeOf(context).width;
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0009)
          ..translate((1 - t) * width * 0.12, 0.0, 0.0)
          ..rotateY((1 - t) * -0.35)
          ..scale(1.0 - 0.05 * o, 1.0 - 0.05 * o);
        return Opacity(
          opacity: (t * 1.4).clamp(0.0, 1.0) * (1 - 0.5 * o),
          child: Transform(alignment: Alignment.centerLeft, transform: m, child: child),
        );
      },
    );
  }
}

ThemeData buildTheme(Color seed, Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Poppins');

  final glassFill = dark ? Colors.white.withValues(alpha: 0.075) : Colors.white.withValues(alpha: 0.72);
  final glassBorder = dark ? Colors.white.withValues(alpha: 0.13) : Colors.white.withValues(alpha: 0.95);
  final solid = dark ? const Color(0xFF14172B) : const Color(0xFFFFFFFF);
  final field = dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.7);
  RoundedRectangleBorder shape(double r, [BorderSide side = BorderSide.none]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r), side: side);

  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: Colors.transparent,
    dividerColor: scheme.onSurface.withValues(alpha: 0.08),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.windows: Depth3DTransitions(),
      TargetPlatform.android: Depth3DTransitions(),
      TargetPlatform.linux: Depth3DTransitions(),
      TargetPlatform.macOS: Depth3DTransitions(),
      TargetPlatform.iOS: Depth3DTransitions(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: glassFill,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: shape(20, BorderSide(color: glassBorder)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: solid,
      surfaceTintColor: Colors.transparent,
      shape: shape(28, BorderSide(color: glassBorder)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: solid,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(
        color: solid, surfaceTintColor: Colors.transparent, shape: shape(16, BorderSide(color: glassBorder))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape(14)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: outline(glassBorder),
      enabledBorder: outline(dark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.10)),
      focusedBorder: outline(scheme.primary, 1.8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: glassBorder),
      backgroundColor: glassFill,
      selectedColor: scheme.primary.withValues(alpha: dark ? 0.35 : 0.22),
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: scheme.onSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape(16),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape(16),
        side: BorderSide(color: glassBorder),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: shape(14))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: const StadiumBorder(),
      elevation: 6,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      extendedTextStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
    ),
    listTileTheme: ListTileThemeData(shape: shape(20), contentPadding: const EdgeInsets.symmetric(horizontal: 16)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: glassFill,
        side: BorderSide(color: glassBorder),
        selectedBackgroundColor: scheme.primary.withValues(alpha: dark ? 0.4 : 0.25),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(strokeCap: StrokeCap.round),
    switchTheme: SwitchThemeData(trackOutlineColor: WidgetStateProperty.all(Colors.transparent)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: solid, borderRadius: BorderRadius.circular(10), border: Border.all(color: glassBorder)),
      textStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: scheme.onSurface),
    ),
  );
}
