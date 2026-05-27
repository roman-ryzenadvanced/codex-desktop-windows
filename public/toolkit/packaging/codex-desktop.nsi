; ═══════════════════════════════════════════════════════════════════════════════
; Codex Desktop - NSIS Installer Script
; ═══════════════════════════════════════════════════════════════════════════════
; Creates a professional Windows installer for Codex Desktop with:
; - Install directory selection
; - File copy from built app
; - Start Menu shortcuts
; - Desktop shortcut (optional)
; - URL protocol handler (codex://)
; - Uninstaller
; - Registry entries for Add/Remove Programs
; ═══════════════════════════════════════════════════════════════════════════════

!define PRODUCT_NAME "Codex Desktop"
!define PRODUCT_VERSION "0.1.0"
!define PRODUCT_PUBLISHER "OpenAI"
!define PRODUCT_WEB_SITE "https://codex.openai.com"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
!define PRODUCT_DIR_REGKEY "Software\${PRODUCT_NAME}"
!define PRODUCT_PROTOCOL "codex"
!define PRODUCT_EXE "electron\electron.exe"
!define PRODUCT_LAUNCHER "start.ps1"

; ─── Installer Settings ──────────────────────────────────────────────────────

Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 32

Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "codex-desktop-${PRODUCT_VERSION}-setup.exe"
InstallDir "$PROGRAMFILES64\${PRODUCT_NAME}"
InstallDirRegKey HKLM "${PRODUCT_DIR_REGKEY}" "InstallDir"

RequestExecutionLevel admin

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "WinVer.nsh"

; ─── MUI Settings ────────────────────────────────────────────────────────────

!define MUI_ABORTWARNING
!define MUI_ICON "packaging\icons\codex.ico"
!define MUI_UNICON "packaging\icons\codex-uninstall.ico"

; Welcome page
!insertmacro MUI_PAGE_WELCOME

; License page
!insertmacro MUI_PAGE_LICENSE "packaging\LICENSE.txt"

; Directory page
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select the directory where ${PRODUCT_NAME} will be installed."
!insertmacro MUI_PAGE_DIRECTORY

; Components page (optional desktop shortcut)
!define MUI_COMPONENTSPAGE_SMALLDESC
!insertmacro MUI_PAGE_COMPONENTS

; Install page
!insertmacro MUI_PAGE_INSTFILES

; Finish page
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_LAUNCHER}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${PRODUCT_NAME}"
!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Create Desktop Shortcut"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION CreateDesktopShortcut
!insertmacro MUI_PAGE_FINISH

; Uninstaller pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Language
!insertmacro MUI_LANGUAGE "English"

; ─── Component Definitions ───────────────────────────────────────────────────

LangString DESC_SecMain ${LANG_ENGLISH} "Core ${PRODUCT_NAME} application files (required)"
LangString DESC_SecDesktop ${LANG_ENGLISH} "Create a desktop shortcut for ${PRODUCT_NAME}"
LangString DESC_SecProtocol ${LANG_ENGLISH} "Register codex:// URL protocol handler"

Section "!Main Application" SecMain
    SectionIn RO

    SetOutPath "$INSTDIR"

    ; ── Core Files ────────────────────────────────────────────────────────

    DetailPrint "Installing ${PRODUCT_NAME} core files..."

    ; Electron runtime
    SetOutPath "$INSTDIR\electron"
    File /r "build\electron\*.*"

    ; Application resources
    SetOutPath "$INSTDIR\resources"
    File "build\resources\app.asar"

    ; Managed Node.js runtime
    SetOutPath "$INSTDIR\resources\node-runtime"
    File /r "build\resources\node-runtime\*.*"

    ; Webview content
    SetOutPath "$INSTDIR\content\webview"
    File /r "build\content\webview\*.*"

    ; Launcher scripts
    SetOutPath "$INSTDIR\launcher"
    File "launcher\webview-server.py"

    SetOutPath "$INSTDIR"
    File "start.ps1"

    ; Build info
    File "build-info.json"

    ; Plugin data
    SetOutPath "$INSTDIR\resources\plugins"
    File /r "build\resources\plugins\*.*"

    ; ── Launcher executable ───────────────────────────────────────────────

    SetOutPath "$INSTDIR"
    File "build\codex-desktop-launcher.exe"

    ; ── Registry Entries ──────────────────────────────────────────────────

    DetailPrint "Writing registry entries..."

    ; Installation directory
    WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "InstallDir" "$INSTDIR"
    WriteRegStr HKLM "${PRODUCT_DIR_REGKEY}" "Version" "${PRODUCT_VERSION}"

    ; Add/Remove Programs
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayIcon" '"$INSTDIR\${PRODUCT_EXE}"'
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "URLUpdateInfo" "${PRODUCT_WEB_SITE}/updates"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "HelpLink" "${PRODUCT_WEB_SITE}/help"
    WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "NoRepair" 1

    ; Calculate installed size
    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${PRODUCT_UNINST_KEY}" "EstimatedSize" "$0"

    ; ── Start Menu Shortcuts ──────────────────────────────────────────────

    DetailPrint "Creating Start Menu shortcuts..."

    CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" \
        "$INSTDIR\codex-desktop-launcher.exe" "" \
        "$INSTDIR\${PRODUCT_EXE}" 0
    CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall ${PRODUCT_NAME}.lnk" \
        "$INSTDIR\uninstall.exe"

    ; ── URL Protocol Handler ──────────────────────────────────────────────

    DetailPrint "Registering codex:// URL protocol handler..."

    WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_PROTOCOL}" "" "URL:${PRODUCT_NAME} Protocol"
    WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_PROTOCOL}" "URL Protocol" ""
    WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_PROTOCOL}\DefaultIcon" "" '"$INSTDIR\${PRODUCT_EXE}",0'
    WriteRegStr HKLM "SOFTWARE\Classes\${PRODUCT_PROTOCOL}\shell\open\command" "" \
        '"$INSTDIR\codex-desktop-launcher.exe" --url "%1"'

    ; ── Uninstaller ───────────────────────────────────────────────────────

    WriteUninstaller "$INSTDIR\uninstall.exe"

SectionEnd

Section "Desktop Shortcut" SecDesktop
    CreateDesktopShortcut
SectionEnd

Section "URL Protocol Handler" SecProtocol
    ; Already registered in main section
    ; This section exists for user visibility and optional removal
SectionEnd

; ─── Section Descriptions ────────────────────────────────────────────────────

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_SecMain)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
    !insertmacro MUI_DESCRIPTION_TEXT ${SecProtocol} $(DESC_SecProtocol)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

; ─── Custom Functions ────────────────────────────────────────────────────────

Function CreateDesktopShortcut
    CreateShortCut "$DESKTOP\${PRODUCT_NAME}.lnk" \
        "$INSTDIR\codex-desktop-launcher.exe" "" \
        "$INSTDIR\${PRODUCT_EXE}" 0
FunctionEnd

Function .onInit
    ; Check Windows version (require Windows 10+)
    ${If} ${AtLeastWin10}
    ${Else}
        MessageBox MB_OK|MB_ICONSTOP \
            "${PRODUCT_NAME} requires Windows 10 or later."
        Abort
    ${EndIf}

    ; Check for existing installation
    ReadRegStr $0 HKLM "${PRODUCT_DIR_REGKEY}" "InstallDir"
    ${If} $0 != ""
        MessageBox MB_YESNO|MB_ICONQUESTION \
            "An existing installation of ${PRODUCT_NAME} was found at $0.$\n$\nWould you like to upgrade?" \
            /SD IDYES IDYES upgrade
        Abort

        upgrade:
        ; Continue with installation (will overwrite)
    ${EndIf}
FunctionEnd

; ─── Uninstaller ─────────────────────────────────────────────────────────────

Section "Uninstall"

    DetailPrint "Uninstalling ${PRODUCT_NAME}..."

    ; Stop running instances
    nsExec::ExecToLog 'taskkill /F /IM "codex-desktop-launcher.exe" 2>NUL'
    nsExec::ExecToLog 'taskkill /F /IM "electron.exe" /FI "WINDOWTITLE eq Codex*" 2>NUL'
    Sleep 1000

    ; Remove files
    RMDir /r /REBOOTOK "$INSTDIR\electron"
    RMDir /r /REBOOTOK "$INSTDIR\resources"
    RMDir /r /REBOOTOK "$INSTDIR\content"
    RMDir /r /REBOOTOK "$INSTDIR\launcher"
    RMDir /r /REBOOTOK "$INSTDIR\hooks"
    Delete /REBOOTOK "$INSTDIR\start.ps1"
    Delete /REBOOTOK "$INSTDIR\build-info.json"
    Delete /REBOOTOK "$INSTDIR\codex-desktop-launcher.exe"
    Delete /REBOOTOK "$INSTDIR\uninstall.exe"
    RMDir /REBOOTOK "$INSTDIR"

    ; Remove Start Menu shortcuts
    RMDir /r "$SMPROGRAMS\${PRODUCT_NAME}"

    ; Remove Desktop shortcut
    Delete "$DESKTOP\${PRODUCT_NAME}.lnk"

    ; Remove registry entries
    DeleteRegKey HKLM "${PRODUCT_UNINST_KEY}"
    DeleteRegKey HKLM "${PRODUCT_DIR_REGKEY}"
    DeleteRegKey HKLM "SOFTWARE\Classes\${PRODUCT_PROTOCOL}"

    ; Remove plugin cache
    RMDir /r "$APPDATA\.codex\plugins\cache"

    ; Remove log directory (optional)
    RMDir /r "$LOCALAPPDATA\codex-desktop\logs"

    ; Remove user data (ask first)
    MessageBox MB_YESNO|MB_ICONQUESTION \
        "Would you like to remove all ${PRODUCT_NAME} user data?$\n$\nThis includes settings, caches, and plugin data." \
        /SD IDNO IDYES removedata
    Goto done

    removedata:
    RMDir /r "$APPDATA\.codex"
    RMDir /r "$LOCALAPPDATA\codex-desktop"
    RMDir /r "$LOCALAPPDATA\codex-update-manager"

    done:

SectionEnd
