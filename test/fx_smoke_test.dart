import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskme/core/theme.dart';
import 'package:taskme/services/settings_service.dart';
import 'package:taskme/widgets/common.dart';
import 'package:taskme/widgets/fx.dart';
import 'package:taskme/widgets/pin_pad.dart';

void main() {
  testWidgets('fx widgets build and animate without errors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    for (final brightness in [Brightness.dark, Brightness.light]) {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            theme: buildTheme(const Color(0xFF4F6BED), brightness),
            builder: (c, child) => AuroraBackground(child: child!),
            home: Scaffold(
              body: ListView(children: [
                Reveal(child: Tilt(child: Glass(blur: true, child: const Text('glass')))),
                const AnimatedRing(value: 0.7, child: Text('7')),
                AnimatedCount(value: 1234.5, format: (v) => v.toStringAsFixed(0)),
                const StatGrid(children: [
                  StatCard(label: 'Spent', value: '₹1', number: 10, format: _f),
                  StatCard(label: 'Income', value: '₹2'),
                ]),
                const GradientText('Hello'),
                const SizedBox(height: 60, child: FloatingIcon(size: 60)),
                PinPad(onComplete: (_) {}),
              ]),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 60));
      await mouse.moveTo(const Offset(150, 80));
      await tester.pump(const Duration(milliseconds: 300));
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    }
  });
}

String _f(double v) => '₹${v.round()}';
