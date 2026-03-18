#!/usr/bin/env bats
# Tests for lib/pkgmgr.sh — package manager abstraction

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
    TMPDIR_TEST=$(mktemp -d)
    MOCK_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$MOCK_BIN"

    # Stubs
    log_debug() { :; }
    log_info()  { :; }
    log_warn()  { :; }
    log_error() { :; }

    source "$PROJECT_DIR/lib/pkgmgr.sh"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "detect_pkgmgr respects PKGMGR_OVERRIDE" {
    PKGMGR_OVERRIDE="dnf"
    detect_pkgmgr
    [[ "$DETECTED_PKGMGR" == "dnf" ]]
}

@test "detect_pkgmgr finds apt" {
    PKGMGR_OVERRIDE=""
    # Mock apt command
    cat > "$MOCK_BIN/apt" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/apt"
    mkdir -p "$TMPDIR_TEST/dpkg"

    # We can't easily mock /var/lib/dpkg, so just test the override path
    PKGMGR_OVERRIDE="apt"
    detect_pkgmgr
    [[ "$DETECTED_PKGMGR" == "apt" ]]
}

@test "pkgmgr_build_summary formats correctly" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=14
    PKG_UPDATES_SECURITY=3
    PKG_UPDATES_CRITICAL=1
    PKG_UPDATES_FLATPAK=2
    PKG_UPDATES_SNAP=0

    local summary
    summary=$(pkgmgr_build_summary)

    echo "$summary" | grep -q "16 update(s) available"
    echo "$summary" | grep -q "1 CRITICAL"
    echo "$summary" | grep -q "3 SECURITY"
    echo "$summary" | grep -q "2 Flatpak"
}

@test "pkgmgr_build_summary with zero flatpak/snap" {
    DETECTED_PKGMGR="apt"
    PKG_UPDATES_TOTAL=5
    PKG_UPDATES_SECURITY=0
    PKG_UPDATES_CRITICAL=0
    PKG_UPDATES_FLATPAK=0
    PKG_UPDATES_SNAP=0

    local summary
    summary=$(pkgmgr_build_summary)

    echo "$summary" | grep -q "5 update(s) available"
    ! echo "$summary" | grep -q "Flatpak"
}

@test "_classify_priority identifies critical packages" {
    [[ "$(_classify_priority "linux-image-6.1")" == "CRITICAL" ]]
    [[ "$(_classify_priority "openssl")" == "CRITICAL" ]]
    [[ "$(_classify_priority "libc6")" == "CRITICAL" ]]
    [[ "$(_classify_priority "systemd")" == "CRITICAL" ]]
    [[ "$(_classify_priority "sudo")" == "CRITICAL" ]]
}

@test "_classify_priority identifies standard packages" {
    [[ "$(_classify_priority "vim")" == "STANDARD" ]]
    [[ "$(_classify_priority "firefox")" == "STANDARD" ]]
    [[ "$(_classify_priority "git")" == "STANDARD" ]]
}

@test "_classify_priority identifies security packages" {
    [[ "$(_classify_priority "vim" "true")" == "SECURITY" ]]
}

@test "pkgmgr_build_preview handles empty list" {
    PKG_UPDATE_LIST=""
    local preview
    preview=$(pkgmgr_build_preview)
    echo "$preview" | grep -q "no package details"
}

@test "pkgmgr_build_preview truncates long lists" {
    PKG_UPDATE_LIST=""
    for i in $(seq 1 35); do
        PKG_UPDATE_LIST+="pkg-$i|1.0|2.0|STANDARD"$'\n'
    done
    PKG_UPDATE_LIST="${PKG_UPDATE_LIST%$'\n'}"

    local preview
    preview=$(pkgmgr_build_preview 30)
    echo "$preview" | grep -q "and .* more"
}

@test "pkgmgr_build_json_packages produces valid JSON array" {
    PKG_UPDATE_LIST="openssl|3.0.10|3.0.11|CRITICAL
vim|9.0|9.1|STANDARD"

    local json
    json=$(pkgmgr_build_json_packages)

    [[ "$json" == *'"name":"openssl"'* ]]
    [[ "$json" == *'"priority":"CRITICAL"'* ]]
    [[ "$json" == *'"name":"vim"'* ]]
    [[ "$json" == \[* ]]
    [[ "$json" == *\] ]]
}

@test "flatpak_available returns 1 when disabled" {
    FLATPAK_ENABLED="false"
    ! flatpak_available
}

@test "snap_available returns 1 when disabled" {
    SNAP_ENABLED="false"
    ! snap_available
}
