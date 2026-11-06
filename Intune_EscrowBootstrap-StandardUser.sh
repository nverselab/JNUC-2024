#!/bin/bash

# Run as root from Intune. Requires an MDM escrow profile for FileVault.
# This script may prompt the logged-in SecureToken user once if bootstrap-token
# escrow is missing. It never reads, rotates, prints, or uploads a FileVault key.

set -u
set -o pipefail
umask 077

PATH=/usr/bin:/bin:/usr/sbin:/sbin
companyName="Your Company"
LOG_TAG="Intune-Escrow"
TEMP_DIR=""
CONSOLE_USER=""
ADMIN_ADDED=0
AUTH_PASSWORD=""

log() {
    /usr/bin/printf '%s\n' "$*"
    /usr/bin/logger -t "$LOG_TAG" "$*" 2>/dev/null || true
}

cleanup() {
    local exit_code=$?
    trap - EXIT HUP INT TERM

    AUTH_PASSWORD=""
    if [[ "$ADMIN_ADDED" -eq 1 ]]; then
        if /usr/sbin/dseditgroup -o edit -d "$CONSOLE_USER" -t user admin; then
            log "Removed temporary admin membership from $CONSOLE_USER."
        else
            log "ERROR: Could not remove temporary admin membership from $CONSOLE_USER; manual review is required."
            exit_code=1
        fi
    fi

    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        /bin/rm -rf "$TEMP_DIR"
    fi

    exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
    log "ERROR: This script must run as root."
    exit 10
fi

if [[ ! -x /usr/bin/profiles || ! -x /usr/sbin/sysadminctl ]]; then
    log "ERROR: Required macOS management commands are unavailable."
    exit 17
fi

bootstrap_status=$(/usr/bin/profiles status -type bootstraptoken 2>&1)
bootstrap_status_rc=$?
if [[ "$bootstrap_status_rc" -ne 0 ]]; then
    log "ERROR: Could not query bootstrap-token status: $bootstrap_status"
    exit 11
fi

if ! /usr/bin/printf '%s\n' "$bootstrap_status" | /usr/bin/grep -Eiq '^[[:space:]]*(profiles:[[:space:]]*)?Bootstrap Token supported on server:[[:space:]]*YES'; then
    log "ERROR: The enrolled MDM does not report bootstrap-token escrow support. Verify enrollment and MDM support."
    exit 11
fi

if /usr/bin/printf '%s\n' "$bootstrap_status" | /usr/bin/grep -Eiq '^[[:space:]]*(profiles:[[:space:]]*)?Bootstrap Token escrowed to server:[[:space:]]*YES'; then
    log "Bootstrap token is already escrowed to the MDM."
else
    CONSOLE_USER=$(/usr/bin/stat -f%Su /dev/console 2>/dev/null || true)
    if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
        log "ERROR: No eligible user is logged in. Retry while a SecureToken-enabled user is signed in."
        exit 12
    fi

    CONSOLE_UID=$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)
    if [[ -z "$CONSOLE_UID" ]]; then
        log "ERROR: Could not determine the logged-in user's UID."
        exit 12
    fi

    secure_token_status=$(/usr/sbin/sysadminctl -secureTokenStatus "$CONSOLE_USER" 2>&1)
    if ! /usr/bin/printf '%s\n' "$secure_token_status" | /usr/bin/grep -Eiq 'Secure token is ENABLED'; then
        log "ERROR: $CONSOLE_USER is not SecureToken-enabled; bootstrap-token escrow cannot be requested for this account."
        exit 13
    fi

    if [[ ! -x /usr/bin/expect || ! -x /usr/bin/osascript ]]; then
        log "ERROR: The system is missing expect or osascript; cannot perform the authorized bootstrap-token attempt."
        exit 17
    fi

    TEMP_DIR=$(/usr/bin/mktemp -d /private/var/tmp/intune-escrow.XXXXXX) || {
        log "ERROR: Could not create a protected temporary directory."
        exit 17
    }
    /bin/chmod 700 "$TEMP_DIR"
    expect_script="$TEMP_DIR/install_bootstrap_token.exp"

    /bin/cat > "$expect_script" <<'EXPECT'
#!/usr/bin/expect -f
log_user 0
set timeout 60
set username [lindex $argv 0]
if {[gets stdin password] < 0} {
    exit 2
}
spawn -noecho /usr/bin/profiles install -type bootstraptoken
expect {
    -re {Enter the admin user name:} {
        send -- "$username\r"
        exp_continue
    }
    -re {Enter the password for user .*:} {
        send -- "$password\r"
        set password ""
        exp_continue
    }
    timeout {
        set password ""
        exit 124
    }
    eof {}
}
set password ""
set child_status [lindex [wait] 3]
if {$child_status != 0} {
    exit 1
}
exit 0
EXPECT
    /bin/chmod 600 "$expect_script"

    prompt_script='on run argv
set company to item 1 of argv
set message to company & " needs to finish setting up your Mac. Please enter your Mac login password to continue. This helps keep your device secure."
set answer to display dialog message default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel"
return text returned of answer
end run'

    log "Requesting one-time authorization from the signed-in user for bootstrap-token escrow."
    AUTH_PASSWORD=$(
        /bin/launchctl asuser "$CONSOLE_UID" \
            /usr/bin/sudo -u "$CONSOLE_USER" \
            /usr/bin/osascript -e "$prompt_script" "$companyName" 2>/dev/null
    ) || {
        log "ERROR: User authorization was cancelled or the sign-in prompt could not be displayed."
        exit 14
    }
    if [[ -z "$AUTH_PASSWORD" ]]; then
        log "ERROR: An empty password was provided; bootstrap-token escrow was not attempted."
        exit 14
    fi

    if ! /usr/bin/id -Gn "$CONSOLE_USER" | /usr/bin/tr ' ' '\n' | /usr/bin/grep -qx admin; then
        if /usr/sbin/dseditgroup -o edit -a "$CONSOLE_USER" -t user admin; then
            ADMIN_ADDED=1
            log "Temporarily added $CONSOLE_USER to the admin group for bootstrap-token authorization."
        else
            log "ERROR: Could not grant temporary authorization for bootstrap-token escrow."
            exit 15
        fi
    fi

    if ! /usr/bin/printf '%s\n' "$AUTH_PASSWORD" | /usr/bin/expect "$expect_script" "$CONSOLE_USER"; then
        AUTH_PASSWORD=""
        log "ERROR: macOS did not complete the bootstrap-token installation."
        exit 15
    fi
    AUTH_PASSWORD=""

    bootstrap_status=$(/usr/bin/profiles status -type bootstraptoken 2>&1)
    bootstrap_status_rc=$?
    if [[ "$bootstrap_status_rc" -ne 0 ]] || ! /usr/bin/printf '%s\n' "$bootstrap_status" | /usr/bin/grep -Eiq '^[[:space:]]*(profiles:[[:space:]]*)?Bootstrap Token escrowed to server:[[:space:]]*YES'; then
        log "ERROR: Bootstrap-token escrow could not be confirmed: $bootstrap_status"
        exit 15
    fi
    log "Bootstrap token is now escrowed to the MDM."
fi

if [[ ! -x /usr/bin/fdesetup ]]; then
    log "ERROR: fdesetup is unavailable; cannot check FileVault state."
    exit 17
fi

filevault_status=$(/usr/bin/fdesetup status 2>&1)
filevault_status_rc=$?
if [[ "$filevault_status_rc" -ne 0 ]]; then
    log "ERROR: Could not query FileVault status: $filevault_status"
    exit 16
fi

if ! /usr/bin/printf '%s\n' "$filevault_status" | /usr/bin/grep -Eiq 'FileVault is On|Encryption in progress'; then
    log "ERROR: FileVault is not enabled. Use the native Intune FileVault policy to enable encryption and escrow the PRK."
    exit 16
fi

log "FileVault is enabled or encrypting. The configured MDM escrow payload must escrow the PRK."
log "This script does not rotate, retrieve, display, or upload the PRK; confirm PRK escrow in Intune."
exit 0
