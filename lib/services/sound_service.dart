import 'package:audioplayers/audioplayers.dart';

import 'settings_service.dart';

/// The app's sounds (your files, bundled in assets/sounds).
enum Sfx {
  income('sounds/income.mp3'),
  expense('sounds/expense.mp3'),
  unlock('sounds/unlock.mp3'),
  journalOpen('sounds/journal_open.mp3');

  const Sfx(this.asset);
  final String asset;
}

/// Plays short sounds without ever making the app wait for them.
class SoundService {
  SoundService(this.settings, {this.silent = false});

  final SettingsService settings;

  /// Never makes a sound (used by tests, where there is no audio device).
  final bool silent;
  final _players = <Sfx, AudioPlayer>{};

  Future<void> init() async {
    try {
      // Mix with whatever else is playing (music) instead of stopping it.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
    } catch (_) {}
  }

  /// Fire and forget. Does nothing when sounds are switched off in Settings.
  void play(Sfx sfx) {
    if (silent || !settings.soundsOn) return;
    _play(sfx);
  }

  Future<void> _play(Sfx sfx) async {
    try {
      final p = _players.putIfAbsent(sfx, () => AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      await p.stop();
      await p.play(AssetSource(sfx.asset));
    } catch (_) {
      // A missing audio device must never break the app.
    }
  }

  Future<void> stop(Sfx sfx) async {
    try {
      await _players[sfx]?.stop();
    } catch (_) {}
  }
}
