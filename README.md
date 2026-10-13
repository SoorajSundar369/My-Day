# My-Day
Mobile and desktop application for personal being such as journal, income expense etc... with realtime mobile and desktop synchronization flutter application

**MyDay** is a private, offline-first personal organiser for **Windows** and **Android**. Everything is stored on your own devices, and the two stay in sync over your home Wi-Fi with no cloud and no account.

## Features
| Area | What you get |
|---|---|
| **Tasks & reminders** | Due dates, repeats, priorities, tags, checklists, notifications (Windows toasts, Android alarms that work with the app closed) |
| **Habits** | Daily / weekday / weekly-target habits, counted habits, streaks, heatmap, completion rates, reminders, optional "no icon" |
| **Money** | Income and expenses, custom categories (save-for-later or one-off), budgets, recurring entries, charts for today / week / month / year / all time / custom, CSV export, receipts |
| **Journal** | 3D book-opening lock screen, own PIN (4 or 6 digits) or the app PIN, formatting, mood, photos, videos, voice notes, handwriting / drawing, location, prompts, "on this day", insights, calendar, one PDF export |
| **Notes, Files, Calendar, Search** | Notes with colours and pinning, a file vault for any file type, a calendar view, search across everything |
| **Lock** | 4-digit PIN, security question with hint after 5 wrong tries, auto-lock, fingerprint unlock on phones (PIN stays as backup) |
| **Sync** | Encrypted device-to-device sync (see below), manual **Sync now**, optional 30-minute background check on the phone |
| **Android widgets** | Add-only home-screen widgets and long-press shortcuts: money, quick journal, tasks & reminders, habits, quick-add bar. They never show anything you wrote earlier |
| **Look** | Light / dark, accent colours, glass and 3D animations with an Off / Subtle / Balanced / Bold control, custom sounds |

## Download
The `Release Version/` folder holds ready-made installers:

* `MyDay-Desktop-Setup-1.6.1.exe` – Windows 10 / 11 (installs for your user, no admin password)
* `MyDay-Mobile-1.6.1.apk` – Android (allow "Install unknown apps" when asked)

The APK is signed with a standard development key: fine for your own devices, not for the Play Store.

## Pairing and sync
* The **computer is the hub** and listens on your Wi-Fi; the **phone connects only while the app is open**, so there is no background battery drain.
* Pair with a **QR code**, a **6-digit PIN** (never sent over the network; it only proves both devices know it), or by showing the phone's QR to the laptop camera.
* All traffic is encrypted with AES-256-GCM using a key made at pairing time. Conflicts are settled by newest edit, and deletes are remembered so items do not come back.
* A brand-new device inherits your name, PIN, security question and journal lock automatically. Two devices that are both already set up keep their own PINs.
* Files up to 10 MB copy automatically; bigger ones ask first.

## Privacy and security notes
* Data never leaves your devices. Use **Settings > Back up everything** for a backup file.
* The journal lock and the PIN are *app-level* locks. They keep people out of the app, but the database is not encrypted on disk.
* Widgets are add-only by design: nothing from your journal, tasks, habits or money is shown on the home screen.

## Build from source
Requirements: Flutter 3.41+ (Dart 3.11+). For Windows also Visual Studio Build Tools with the **C++ desktop workload and ATL**. For Android the Android SDK.

```bash
flutter pub get
flutter test                      # automated tests
flutter run -d windows            # or: flutter run -d <your phone>
flutter build windows --release   # Windows app
flutter build apk --release       # Android app
```

The Windows installer is built from `installer/myday_setup.iss` with [Inno Setup 6](https://jrsoftware.org/isinfo.php) after `flutter build windows --release`.

### Project layout
```
lib/data      database, models, stores (tasks, habits, money, journal)
lib/sync      encrypted sync engine, pairing (QR / PIN / webcam), screens
lib/journal   journal lock, editor, drawing pad, PDF export
lib/quick     add-only forms opened by widgets and shortcuts
lib/screens   main screens          lib/widgets  shared UI and effects
android/…/widgets   native Android home-screen widgets (Kotlin)
test          automated tests (database, sync over real sockets, pairing, journal, UI flows)
```

## Credits
* Font: [Poppins](https://fonts.google.com/specimen/Poppins) (SIL Open Font License).
* Widget icon shapes follow the style of [Tabler Icons](https://tabler.io/icons) (MIT).
* The four sound effects in `assets/sounds` are the author's own.
* Built with Flutter and the packages listed in `pubspec.yaml`.
