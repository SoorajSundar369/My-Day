import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'lock_controller.dart';
import 'settings_service.dart';

/// Window, system tray and start-with-Windows handling (desktop only).
class DesktopService with TrayListener, WindowListener {
  DesktopService(this.settings, this.lock);

  final SettingsService settings;
  final LockController lock;

  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init({bool startHidden = false}) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1180, 760),
        minimumSize: const Size(420, 560),
        center: true,
        title: settings.appName,
      ),
      () async {
        await windowManager.setPreventClose(true);
        if (startHidden && settings.minimizeToTray) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    windowManager.addListener(this);

    trayManager.addListener(this);
    await trayManager.setIcon('assets/app_icon.ico');
    await trayManager.setToolTip(settings.appName);
    await rebuildTrayMenu();

    final info = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: info.appName,
      appPath: Platform.resolvedExecutable,
      args: const ['--hidden'],
    );
    await applyStartup();
  }

  Future<void> rebuildTrayMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Open ${settings.appName}'),
      MenuItem(key: 'lock', label: 'Lock now'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  }

  Future<void> applyStartup() async {
    if (!supported) return;
    if (settings.startWithWindows) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'lock':
        lock.lock();
        showWindow();
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  void onWindowClose() async {
    if (settings.minimizeToTray) {
      if (settings.lockOnTray) lock.lock();
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }
}
