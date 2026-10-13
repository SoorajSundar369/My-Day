import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/biometric_service.dart';
import '../services/settings_service.dart';

/// Settings switches for fingerprint unlock (shown on phones only).
class BiometricTiles extends StatefulWidget {
  const BiometricTiles({super.key});

  @override
  State<BiometricTiles> createState() => _BiometricTilesState();
}

class _BiometricTilesState extends State<BiometricTiles> {
  bool _available = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    context.read<BiometricService>().available().then((v) {
      if (mounted) setState(() {
            _available = v;
            _checked = true;
          });
    });
  }

  Future<void> _toggle(String key, bool on) async {
    final s = context.read<SettingsService>();
    if (on) {
      final ok = await context.read<BiometricService>().authenticate('Touch the sensor to turn this on', closeLabel: 'Cancel');
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not confirm your fingerprint, so it was not turned on.')));
        }
        return;
      }
    }
    await s.set(key, on);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    final hint = !_checked
        ? 'Checking this phone…'
        : (_available ? 'Your PIN still works as a backup' : 'Add a fingerprint in your phone settings first');
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: const Text('Unlock with fingerprint'),
        subtitle: Text(hint),
        value: s.bioApp,
        onChanged: _available ? (v) => _toggle('bioApp', v) : null,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.menu_book_outlined),
        title: const Text('Open the journal with fingerprint'),
        subtitle: const Text('Instead of typing the journal PIN'),
        value: s.bioJournal,
        onChanged: _available ? (v) => _toggle('bioJournal', v) : null,
      ),
    ]);
  }
}
