#!/bin/bash

set -Eeuo pipefail

WECHAT="/Applications/WeChat.app"
WECHAT2="/Applications/WeChat2.app"
WECHAT2_OLD="/Applications/WeChat2.old.app"

MAIN_BUNDLE_ID="com.tencent.xinWeChat"
SECOND_BUNDLE_ID="com.tencent.xinWeChat2"

# Process-match patterns (ERE, dots escaped). Matching on /Contents/ limits
# the match to processes actually running from the bundles.
WECHAT_PROC_PATTERN='/Applications/WeChat\.app/Contents/'
WECHAT2_PROC_PATTERN='/Applications/WeChat2\.app/Contents/'

PLISTBUDDY="/usr/libexec/PlistBuddy"

ASSUME_YES=0

# ---------- Helpers ----------

info() {
    printf "\033[1;34m==>\033[0m %s\n" "$1"
}

success() {
    printf "\033[1;32m✓\033[0m %s\n" "$1"
}

warn() {
    printf "\033[1;33m!\033[0m %s\n" "$1"
}

error() {
    printf "\033[1;31m✗\033[0m %s\n" "$1" >&2
}

die() {
    error "$1"
    exit 1
}

require_sudo() {
    info "Administrator privileges are required."
    sudo -v || die "Unable to obtain administrator privileges."
}

human_kb() {
    awk -v kb="$1" 'BEGIN {
        split("KB MB GB TB", unit, " ")
        i = 1
        while (kb >= 1024 && i < 4) {
            kb /= 1024
            i++
        }
        printf "%.1f %s", kb, unit[i]
    }'
}

require_disk_space() {
    local src="$1"
    local needed available

    needed="$(du -sk "$src" 2>/dev/null | awk '{print $1}')" || needed=""
    available="$(df -kP /Applications 2>/dev/null | awk 'NR==2 {print $4}')" || \
        available=""

    if [ -z "$needed" ] || [ -z "$available" ]; then
        warn "Unable to determine disk usage. Skipping disk space check."
        return 0
    fi

    case "$needed$available" in
        *[!0-9]*)
            warn "Unable to determine disk usage. Skipping disk space check."
            return 0
            ;;
    esac

    # The copy is re-signed afterwards, so leave a 10% margin.
    needed=$(( needed + needed / 10 ))

    if [ "$available" -lt "$needed" ]; then
        die "Not enough free space in /Applications.
  Required:  $(human_kb "$needed")
  Available: $(human_kb "$available")"
    fi

    info "Free space: $(human_kb "$available") (need $(human_kb "$needed"))"
}

confirm_risk() {
    local action="$1"

    echo
    warn "Please review before continuing:"
    echo
    echo "  - This is an unofficial workaround, not endorsed by Tencent."
    echo "  - The modified app is ad-hoc signed, not signed by Tencent."
    echo "  - A future WeChat or macOS update may break this method."

    case "$action" in
        install)
            echo "  - WeChat and WeChat2 will be closed."
            echo "  - WeChat2.app will be created in /Applications."
            ;;
        update)
            echo "  - WeChat and WeChat2 will be closed."
            echo "  - Current WeChat2.app will be replaced."
            echo "  - The previous version is kept as WeChat2.old.app."
            ;;
        rollback)
            echo "  - WeChat and WeChat2 will be closed."
            echo "  - Current WeChat2.app will be deleted."
            echo "  - WeChat2.old.app will be restored."
            ;;
        uninstall)
            echo "  - WeChat2 will be closed."
            echo "  - WeChat2.app will be deleted from /Applications."
            echo "  - WeChat2.old.app will be deleted if present."
            ;;
    esac

    echo "  - Chat data under ~/Library/Containers is NOT touched."
    echo

    if [ "$ASSUME_YES" = "1" ]; then
        info "Confirmation skipped (--yes)."
        return
    fi

    printf "Continue? [y/N] "
    read -r reply || true

    case "${reply:-}" in
        y|Y|yes|YES)
            ;;
        *)
            info "Aborted. No changes were made."
            exit 0
            ;;
    esac
}

get_bundle_id() {
    "$PLISTBUDDY" -c "Print :CFBundleIdentifier" \
        "$1/Contents/Info.plist"
}

get_version() {
    "$PLISTBUDDY" -c "Print :CFBundleShortVersionString" \
        "$1/Contents/Info.plist"
}

check_main_wechat() {
    [ -d "$WECHAT" ] || die "WeChat.app not found in /Applications."

    local bundle_id
    bundle_id="$(get_bundle_id "$WECHAT")" || \
        die "Unable to read WeChat Bundle ID from Info.plist."

    [ "$bundle_id" = "$MAIN_BUNDLE_ID" ] || \
        die "Unexpected WeChat Bundle ID: $bundle_id"
}

# Wait up to 5 seconds for processes matching $1 to exit. Returns non-zero
# if any are still running.
wait_for_pattern_exit() {
    for _ in 1 2 3 4 5; do
        pgrep -f "$1" >/dev/null 2>&1 || return 0
        sleep 1
    done

    return 1
}

# Wait up to 5 seconds for both apps to exit. Returns non-zero if either
# is still running.
wait_for_exit() {
    for _ in 1 2 3 4 5; do
        if ! pgrep -f "$WECHAT_PROC_PATTERN" >/dev/null 2>&1 && \
           ! pgrep -f "$WECHAT2_PROC_PATTERN" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

quit_wechat() {
    info "Closing WeChat instances..."

    osascript -e 'tell application id "com.tencent.xinWeChat" to quit' \
        2>/dev/null || true

    osascript -e 'tell application id "com.tencent.xinWeChat2" to quit' \
        2>/dev/null || true

    wait_for_exit || true

    # Fallback if either app did not exit cleanly.
    pkill -f "$WECHAT_PROC_PATTERN" 2>/dev/null || true
    pkill -f "$WECHAT2_PROC_PATTERN" 2>/dev/null || true

    # SIGTERM may take a few seconds to tear the apps down.
    wait_for_exit || true

    # Reading from a still-running WeChat.app could produce a corrupt copy,
    # and a still-running WeChat2 confuses the launch of the new bundle.
    if pgrep -f "$WECHAT_PROC_PATTERN" >/dev/null 2>&1; then
        die "WeChat is still running. Close it manually and retry."
    fi

    if pgrep -f "$WECHAT2_PROC_PATTERN" >/dev/null 2>&1; then
        die "WeChat2 is still running. Close it manually and retry."
    fi
}

# Uninstall only needs WeChat2 gone, so the official WeChat is left alone.
quit_wechat2() {
    info "Closing WeChat2..."

    osascript -e 'tell application id "com.tencent.xinWeChat2" to quit' \
        2>/dev/null || true

    wait_for_pattern_exit "$WECHAT2_PROC_PATTERN" || true

    pkill -f "$WECHAT2_PROC_PATTERN" 2>/dev/null || true

    wait_for_pattern_exit "$WECHAT2_PROC_PATTERN" || true

    if pgrep -f "$WECHAT2_PROC_PATTERN" >/dev/null 2>&1; then
        die "WeChat2 is still running. Close it manually and retry."
    fi
}

copy_and_patch() {
    info "Copying latest WeChat.app..."

    # ditto preserves metadata, extended attributes, and resource forks.
    sudo ditto "$WECHAT" "$WECHAT2"

    info "Changing Bundle ID to $SECOND_BUNDLE_ID..."

    sudo "$PLISTBUDDY" \
        -c "Set :CFBundleIdentifier $SECOND_BUNDLE_ID" \
        "$WECHAT2/Contents/Info.plist"

    local bundle_id
    bundle_id="$(get_bundle_id "$WECHAT2")" || {
        error "Unable to read WeChat2 Bundle ID from Info.plist."
        return 1
    }

    # Return instead of die: exit would skip the ERR trap and leave the
    # incomplete WeChat2.app behind with no cleanup or rollback.
    if [ "$bundle_id" != "$SECOND_BUNDLE_ID" ]; then
        error "Failed to change Bundle ID."
        return 1
    fi

    # Remove the quarantine attribute copied from the downloaded WeChat.app,
    # otherwise Gatekeeper may block the re-signed copy.
    info "Clearing quarantine attributes..."

    sudo xattr -cr "$WECHAT2"

    info "Re-signing WeChat2.app..."

    sudo codesign \
        --force \
        --deep \
        --sign - \
        "$WECHAT2"

    info "Verifying signature..."

    codesign \
        --verify \
        --deep \
        --strict \
        --verbose=2 \
        "$WECHAT2"

    success "Signature verification passed."
}

# ---------- Commands ----------

install_failed() {
    trap - ERR INT TERM

    error "Installation failed."

    if [ -d "$WECHAT2" ]; then
        warn "Removing incomplete WeChat2.app..."
        sudo rm -rf "$WECHAT2" || true
    fi

    exit 1
}

install_wechat2() {
    check_main_wechat

    if [ -d "$WECHAT2" ]; then
        local existing_bundle
        existing_bundle="$(get_bundle_id "$WECHAT2" 2>/dev/null)" || \
            existing_bundle="(unknown)"

        if [ "$existing_bundle" = "$SECOND_BUNDLE_ID" ]; then
            die "WeChat2.app already exists. Use '$0 update' instead."
        fi

        die "WeChat2.app exists but its Bundle ID is $existing_bundle.
Remove the incomplete copy and retry:
  sudo rm -rf \"$WECHAT2\"
  $0 install"
    fi

    require_disk_space "$WECHAT"

    confirm_risk install
    require_sudo

    quit_wechat

    trap 'install_failed' ERR INT TERM

    copy_and_patch

    trap - ERR INT TERM

    success "WeChat2 installed successfully."

    echo
    status_wechat

    echo
    info "Starting WeChat2..."

    open "$WECHAT2"
}

update_wechat2() {
    check_main_wechat

    [ -d "$WECHAT2" ] || \
        die "WeChat2.app does not exist. Use '$0 install' first."

    local current_bundle
    current_bundle="$(get_bundle_id "$WECHAT2")" || \
        die "Unable to read WeChat2 Bundle ID from Info.plist."

    [ "$current_bundle" = "$SECOND_BUNDLE_ID" ] || \
        die "Unexpected WeChat2 Bundle ID: $current_bundle
Remove the copy and reinstall:
  sudo rm -rf \"$WECHAT2\"
  $0 install"

    local main_version second_version

    main_version="$(get_version "$WECHAT")" || \
        die "Unable to read WeChat version."
    second_version="$(get_version "$WECHAT2")" || \
        die "Unable to read WeChat2 version."

    info "WeChat version:  $main_version"
    info "WeChat2 version: $second_version"

    if [ "$main_version" = "$second_version" ]; then
        warn "WeChat2 is already the same version as WeChat."
        return
    fi

    # Must run before the backup is moved: die exits without triggering
    # the ERR trap, which would leave no WeChat2.app at all.
    require_disk_space "$WECHAT"

    confirm_risk update
    require_sudo

    quit_wechat

    if [ -d "$WECHAT2_OLD" ]; then
        info "Removing previous WeChat2.old.app..."
        sudo rm -rf "$WECHAT2_OLD"
    fi

    info "Backing up current WeChat2.app..."

    sudo mv "$WECHAT2" "$WECHAT2_OLD"

    # Roll back automatically if anything fails or the user interrupts.
    trap 'update_failed' ERR INT TERM

    copy_and_patch

    trap - ERR INT TERM

    success "WeChat2 updated successfully."

    echo
    status_wechat

    echo
    info "Starting updated WeChat2..."

    open "$WECHAT2"

    echo
    warn "Backup retained at:"
    echo "  $WECHAT2_OLD"
    echo
    echo "After confirming WeChat2 works correctly:"
    echo "  sudo rm -rf \"$WECHAT2_OLD\""
}

update_failed() {
    trap - ERR INT TERM

    error "Update failed."

    if [ -d "$WECHAT2" ]; then
        sudo rm -rf "$WECHAT2" || true
    fi

    if [ -d "$WECHAT2_OLD" ]; then
        warn "Restoring previous WeChat2.app..."
        sudo mv "$WECHAT2_OLD" "$WECHAT2"
        success "Rollback completed."
    fi

    exit 1
}

rollback_wechat2() {
    [ -d "$WECHAT2_OLD" ] || \
        die "No WeChat2.old.app backup found."

    confirm_risk rollback
    require_sudo

    quit_wechat

    if [ -d "$WECHAT2" ]; then
        info "Removing current WeChat2.app..."
        sudo rm -rf "$WECHAT2"
    fi

    info "Restoring WeChat2.old.app..."

    sudo mv "$WECHAT2_OLD" "$WECHAT2"

    success "Rollback completed."

    echo
    status_wechat

    open "$WECHAT2"
}

uninstall_wechat2() {
    if [ ! -d "$WECHAT2" ] && [ ! -d "$WECHAT2_OLD" ]; then
        die "Nothing to uninstall."
    fi

    confirm_risk uninstall
    require_sudo

    quit_wechat2

    if [ -d "$WECHAT2" ]; then
        info "Removing WeChat2.app..."
        sudo rm -rf "$WECHAT2"
    fi

    if [ -d "$WECHAT2_OLD" ]; then
        info "Removing WeChat2.old.app..."
        sudo rm -rf "$WECHAT2_OLD"
    fi

    success "WeChat2 uninstalled."

    echo
    info "Chat data was NOT touched."
    echo "To remove it as well (your terminal needs Full Disk Access):"
    echo "  rm -rf \"$HOME/Library/Containers/$SECOND_BUNDLE_ID\""
}

status_wechat() {
    local v b

    echo "----------------------------------------"

    if [ -d "$WECHAT" ]; then
        echo "WeChat"
        v="$(get_version "$WECHAT" 2>/dev/null)" || v="(unknown)"
        b="$(get_bundle_id "$WECHAT" 2>/dev/null)" || b="(unknown)"
        echo "  Version:   $v"
        echo "  Bundle ID: $b"
    else
        echo "WeChat"
        echo "  Not installed"
    fi

    echo

    if [ -d "$WECHAT2" ]; then
        echo "WeChat2"
        v="$(get_version "$WECHAT2" 2>/dev/null)" || v="(unknown)"
        b="$(get_bundle_id "$WECHAT2" 2>/dev/null)" || b="(unknown)"
        echo "  Version:   $v"
        echo "  Bundle ID: $b"
    else
        echo "WeChat2"
        echo "  Not installed"
    fi

    echo

    if [ -d "$WECHAT2_OLD" ]; then
        echo "Backup"
        echo "  $WECHAT2_OLD"
    else
        echo "Backup"
        echo "  None"
    fi

    echo "----------------------------------------"
}

usage() {
    cat <<EOF
Usage:

  $0 install
      Create WeChat2.app from the installed WeChat.app.

  $0 update
      Update WeChat2.app after the official WeChat.app is updated.

  $0 status
      Show versions and Bundle IDs.

  $0 rollback
      Restore WeChat2.old.app after a failed/problematic update.

  $0 uninstall
      Remove WeChat2.app and WeChat2.old.app.

  $0 help
      Show this help.

Options:

  -y, --yes
      Skip the interactive risk confirmation.
EOF
}

COMMAND=""

for arg in "$@"; do
    case "$arg" in
        -y|--yes)
            ASSUME_YES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $arg"
            echo
            usage
            exit 1
            ;;
        *)
            if [ -n "$COMMAND" ]; then
                error "Unexpected argument: $arg"
                echo
                usage
                exit 1
            fi
            COMMAND="$arg"
            ;;
    esac
done

# Running as root would launch WeChat2 as root and create its sandbox
# container in the wrong home directory. The script calls sudo itself.
case "$COMMAND" in
    install|update|rollback|uninstall)
        [ "$(id -u)" -ne 0 ] || \
            die "Do not run this script with sudo. Run it as your normal user:
  $0 $COMMAND"
        ;;
esac

case "$COMMAND" in
    install)
        install_wechat2
        ;;
    update)
        update_wechat2
        ;;
    status)
        status_wechat
        ;;
    rollback)
        rollback_wechat2
        ;;
    uninstall)
        uninstall_wechat2
        ;;
    help|-h|--help|"")
        usage
        ;;
    *)
        error "Unknown command: $COMMAND"
        echo
        usage
        exit 1
        ;;
esac