; CubicLM Windows installer (Inno Setup 6).
; Requires: Inno Setup (https://jrsoftware.org/isdl.php)
; Build the app first, then run from the repo root:
;   flutter build windows --release
;   iscc /DAppVersion=1.7.0 windows\installer\cubiclm.iss
; Output: windows\installer\Output\CubicLM-Setup-<version>.exe
; NOTE: unsigned build (no prod cert committed). For a signed installer,
; add your PFX path + password to SignTool and uncomment below.

#ifndef AppVersion
  #define AppVersion "1.7.0"
#endif

[Setup]
AppId={{3C7B1A2E-9F4D-4C8A-B6E2-7D5A1F3C9E42}
AppName=CubicLM
AppVersion={#AppVersion}
AppPublisher=CubicLM
DefaultDirName={autopf}\CubicLM
DefaultGroupName=CubicLM
OutputDir=Output
OutputBaseFilename=CubicLM-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
;SignTool=signtool sign /fd SHA256 /f $qcert.pfx$q /p $qpassword$q $f

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\CubicLM"; Filename: "{app}\cubiclm.exe"
Name: "{autodesktop}\CubicLM"; Filename: "{app}\cubiclm.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; Flags: unchecked

[Run]
Filename: "{app}\cubiclm.exe"; Description: "Launch CubicLM"; Flags: nowait postinstall skipifsilent
