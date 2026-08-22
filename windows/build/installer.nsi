Unicode true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!include "MUI2.nsh"

!define PRODUCT_NAME "Recast"
!define PRODUCT_VERSION "1.0.0"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Recast"

Name "${PRODUCT_NAME}"
OutFile "..\release\Recast-1.0.0-Windows-x64-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Recast"
InstallDirRegKey HKCU "Software\Luke McLaughlin\Recast" "InstallLocation"
Icon "icon.ico"
UninstallIcon "icon.ico"
BrandingText "Recast for Windows 11"
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "1.0.0.0"
VIAddVersionKey /LANG=1033 "ProductName" "Recast"
VIAddVersionKey /LANG=1033 "CompanyName" "Luke McLaughlin"
VIAddVersionKey /LANG=1033 "FileDescription" "Universal on-device file converter for Windows 11"
VIAddVersionKey /LANG=1033 "FileVersion" "1.0.0"
VIAddVersionKey /LANG=1033 "ProductVersion" "1.0.0"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright Luke McLaughlin"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "..\release\win-unpacked\*.*"
  CreateDirectory "$SMPROGRAMS\Recast"
  CreateShortCut "$SMPROGRAMS\Recast\Recast.lnk" "$INSTDIR\Recast.exe"
  CreateShortCut "$DESKTOP\Recast.lnk" "$INSTDIR\Recast.exe"
  WriteUninstaller "$INSTDIR\Uninstall Recast.exe"
  WriteRegStr HKCU "Software\Luke McLaughlin\Recast" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Recast"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "1.0.0"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Luke McLaughlin"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Recast.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall Recast.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall Recast.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$DESKTOP\Recast.lnk"
  Delete "$SMPROGRAMS\Recast\Recast.lnk"
  RMDir "$SMPROGRAMS\Recast"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\Luke McLaughlin\Recast"
  RMDir /r "$INSTDIR"
SectionEnd
