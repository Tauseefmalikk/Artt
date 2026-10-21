#!/usr/bin/env bash
# ============================================================================
# Atomic Red Team - 1-Click Master Simulation Runner for macOS & Linux
# Double-click this file in macOS Finder or run via Terminal.
# ============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo ""
echo "============================================================"
echo "  Atomic Red Team - 1-Click Simulation Runner (macOS/Linux)  "
echo "============================================================"
echo ""

# 1. Ensure standard binary directories are in PATH
for p in "/usr/local/bin" "/opt/homebrew/bin" "/opt/microsoft/powershell/7"; do
    if [ -d "$p" ] && [[ ":$PATH:" != *":$p:"* ]]; then
        export PATH="$p:$PATH"
    fi
done

# 2. Check for PowerShell Core (pwsh) or install it automatically
PWSH_BIN=""
if command -v pwsh >/dev/null 2>&1; then
    PWSH_BIN="$(command -v pwsh)"
elif [ -x "/usr/local/bin/pwsh" ]; then
    PWSH_BIN="/usr/local/bin/pwsh"
elif [ -x "/opt/homebrew/bin/pwsh" ]; then
    PWSH_BIN="/opt/homebrew/bin/pwsh"
elif [ -x "/opt/microsoft/powershell/7/pwsh" ]; then
    PWSH_BIN="/opt/microsoft/powershell/7/pwsh"
fi

if [ -z "$PWSH_BIN" ]; then
    echo "[!] PowerShell Core ('pwsh') is not installed on this machine."
    echo "[+] Auto-Dependency Setup: Installing PowerShell Core for macOS..."
    echo ""

    INSTALLED=0

    # Option A: Try Homebrew if available
    BREW_BIN=""
    if command -v brew >/dev/null 2>&1; then
        BREW_BIN="$(command -v brew)"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [ -x "/usr/local/bin/brew" ]; then
        BREW_BIN="/usr/local/bin/brew"
    fi

    if [ -n "$BREW_BIN" ]; then
        echo "  [1/2] Installing via Homebrew..."
        "$BREW_BIN" install --cask powershell && INSTALLED=1
    fi

    # Option B: Fallback to direct official Microsoft PKG installer via curl
    if [ $INSTALLED -eq 0 ]; then
        echo "  [2/2] Downloading official Microsoft PowerShell package..."
        ARCH=$(uname -m)
        if [ "$ARCH" = "arm64" ]; then
            PKG_URL="https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-osx-arm64.pkg"
        else
            PKG_URL="https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-osx-x64.pkg"
        fi

        TMP_PKG="/tmp/powershell_install_$$.pkg"
        echo "      Downloading from: $PKG_URL"
        if curl -fSL --progress-bar -o "$TMP_PKG" "$PKG_URL"; then
            echo "      Installing package (administrator password required)..."
            sudo installer -pkg "$TMP_PKG" -target /
            rm -f "$TMP_PKG"
            INSTALLED=1
        else
            echo "  [ERROR] Download failed. Please check internet connection."
        fi
    fi

    # Re-detect pwsh
    if [ -x "/usr/local/bin/pwsh" ]; then
        PWSH_BIN="/usr/local/bin/pwsh"
    elif [ -x "/opt/homebrew/bin/pwsh" ]; then
        PWSH_BIN="/opt/homebrew/bin/pwsh"
    elif command -v pwsh >/dev/null 2>&1; then
        PWSH_BIN="$(command -v pwsh)"
    fi

    if [ -z "$PWSH_BIN" ]; then
        echo ""
        echo "[ERROR] Could not install or locate PowerShell Core."
        echo "Please install it manually: brew install --cask powershell"
        read -p "Press [Enter] to exit..."
        exit 1
    fi

    echo "  [OK] PowerShell Core successfully installed at: $PWSH_BIN"
    echo ""
fi

# 3. Locate Start-ARTAutomation.ps1
TARGET_SCRIPT=""
if [ -f "$DIR/ART-main/scripts/Start-ARTAutomation.ps1" ]; then
    TARGET_SCRIPT="$DIR/ART-main/scripts/Start-ARTAutomation.ps1"
elif [ -f "$DIR/scripts/Start-ARTAutomation.ps1" ]; then
    TARGET_SCRIPT="$DIR/scripts/Start-ARTAutomation.ps1"
elif [ -f "$DIR/Artt-main/ART-main/scripts/Start-ARTAutomation.ps1" ]; then
    TARGET_SCRIPT="$DIR/Artt-main/ART-main/scripts/Start-ARTAutomation.ps1"
fi

if [ -z "$TARGET_SCRIPT" ]; then
    echo "[ERROR] Could not find Start-ARTAutomation.ps1!"
    echo "Please ensure the repository files are intact."
    read -p "Press [Enter] to exit..."
    exit 1
fi

# 4. Check for root (sudo) elevation and execute
if [ "$EUID" -ne 0 ]; then
    echo "Administrator (root) privileges are required to simulate security attacks."
    echo "Requesting sudo permissions..."
    echo ""
    sudo "$PWSH_BIN" -NoProfile -ExecutionPolicy Bypass -File "$TARGET_SCRIPT" "$@"
else
    "$PWSH_BIN" -NoProfile -ExecutionPolicy Bypass -File "$TARGET_SCRIPT" "$@"
fi

EXIT_CODE=$?
echo ""
echo "============================================================"
echo " Execution finished (exit code $EXIT_CODE)."
echo "============================================================"
read -p "Press [Enter] to close this window..."
