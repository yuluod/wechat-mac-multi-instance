#!/bin/bash

set -Eeuo pipefail

WECHAT="/Applications/WeChat.app"
WECHAT2="/Applications/WeChat2.app"
WECHAT2_OLD="/Applications/WeChat2.old.app"

MAIN_BUNDLE_ID="com.tencent.xinWeChat"
SECOND_BUNDLE_ID="com.tencent.xinWeChat2"

PLISTBUDDY="/usr/libexec/PlistBuddy"

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
    bundle_id="$(get_bundle_id "$WECHAT")"

    [ "$bundle_id" = "$MAIN_BUNDLE_ID" ] || \
        die "Unexpected WeChat Bundle ID: $bundle_id"
}

quit_wechat() {
    info "Closing WeChat instances..."

    osascript -e 'tell application id "com.tencent.xinWeChat" to quit' \
        2>/dev/null || true

    osascript -e 'tell application id "com.tencent.xinWeChat2" to quit' \
        2>/dev/null || true

    for _ in 1 2 3 4 5; do
        if ! pgrep -f '/Applications/WeChat2.app/' >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    # Fallback for WeChat2 if it did not exit cleanly.
    pkill -f '/Applications/WeChat2.app/' 2>/dev/null || true

    sleep 1
}

copy_and_patch() {
    info "Copying latest WeChat.app..."

    sudo cp -R "$WECHAT" "$WECHAT2"

    info "Changing Bundle ID to $SECOND_BUNDLE_ID..."

    sudo "$PLISTBUDDY" \
        -c "Set :CFBundleIdentifier $SECOND_BUNDLE_ID" \
        "$WECHAT2/Contents/Info.plist"

    local bundle_id
    bundle_id="$(get_bundle_id "$WECHAT2")"

    [ "$bundle_id" = "$SECOND_BUNDLE_ID" ] || \
        die "Failed to change Bundle ID."

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
    trap - ERR

    error "Installation failed."

    if [ -d "$WECHAT2" ]; then
        warn "Removing incomplete WeChat2.app..."
        sudo rm -rf "$WECHAT2" || true
    fi

    exit 1
}

install_wechat2() {
    check_main_wechat
    require_sudo

    if [ -d "$WECHAT2" ]; then
        die "WeChat2.app already exists. Use '$0 update' instead."
    fi

    quit_wechat

    trap 'install_failed' ERR

    copy_and_patch

    trap - ERR

    success "WeChat2 installed successfully."

    echo
    status_wechat

    echo
    info "Starting WeChat2..."

    open "$WECHAT2"
}

update_wechat2() {
    check_main_wechat
    require_sudo

    [ -d "$WECHAT2" ] || \
        die "WeChat2.app does not exist. Use '$0 install' first."

    local current_bundle
    current_bundle="$(get_bundle_id "$WECHAT2")"

    [ "$current_bundle" = "$SECOND_BUNDLE_ID" ] || \
        die "Unexpected WeChat2 Bundle ID: $current_bundle"

    local main_version second_version

    main_version="$(get_version "$WECHAT")"
    second_version="$(get_version "$WECHAT2")"

    info "WeChat version:  $main_version"
    info "WeChat2 version: $second_version"

    if [ "$main_version" = "$second_version" ]; then
        warn "WeChat2 is already the same version as WeChat."
        return
    fi

    quit_wechat

    if [ -d "$WECHAT2_OLD" ]; then
        info "Removing previous WeChat2.old.app..."
        sudo rm -rf "$WECHAT2_OLD"
    fi

    info "Backing up current WeChat2.app..."

    sudo mv "$WECHAT2" "$WECHAT2_OLD"

    # Roll back automatically if anything fails.
    trap 'update_failed' ERR

    copy_and_patch

    trap - ERR

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
    trap - ERR

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
    require_sudo

    [ -d "$WECHAT2_OLD" ] || \
        die "No WeChat2.old.app backup found."

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

  $0 help
      Show this help.
EOF
}

case "${1:-}" in
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
    help|-h|--help|"")
        usage
        ;;
    *)
        error "Unknown command: $1"
        echo
        usage
        exit 1
        ;;
esac