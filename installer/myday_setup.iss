; Inno Setup script for MyDay (Windows desktop build)
; Produces a single-file installer: installs per-user (no admin password needed),
; adds Start menu + optional desktop shortcuts, and registers an uninstaller.
; Your tasks, notes, files and settings live in %APPDATA%\com.sujay\taskme and are
; NOT removed on uninstall, so reinstalling or upgrading never loses data.

#define MyAppName "MyDay"
#define MyAppVersion "1.6.1"
#define MyAppPublisher "Sooraj"
#define MyAppExeName "MyDay.exe"
; Path to the Flutter Windows release output, relative to this script.
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
; A fixed GUID lets future versions upgrade this install in place.
AppId={{7B3E5A91-0C42-4D7E-A8F6-3E19B2C45D80}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=MyDay-Setup-{#MyAppVersion}
SetupIconFile=..\assets\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Excludes: "*.old.exe"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
