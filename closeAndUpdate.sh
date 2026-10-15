#!/bin/bash
#
# closeAndUpdate.sh
# Close FileMaker databases and install package updates.
#
# Run latest version of the script.
# Note: Replace $FMS_USER and $FMS_PASS if the FMS environment variables have not been configured.
# curl -fsSL https://raw.githubusercontent.com/Codence-Developers/filemakerLinux/main/closeAndUpdate.sh | bash -s -- -u $FMS_USER -p $FMS_PASS

set -e

# Initialize variables
FMS_USER=""
FMS_PASS=""

# Function to display script usage
usage() {
    local exit_code="${1:-1}"
    echo "Usage: $(basename "$0") -u <FMS_USER> -p <FMS_PASS>"
    echo ""
    echo "Required arguments:"
    echo "  -u, --user VALUE       FileMaker Server Admin Console username"
    echo "  -p, --pass VALUE       FileMaker Server Admin Console password"
    echo ""
    echo "Optional arguments:"
    echo "  -h, --help             Display this help message"
    exit "$exit_code"
}

# Ensure script is executed with root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user|--username)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: Argument for $1 is missing." >&2
                usage
            fi
            FMS_USER="$2"
            shift 2
            ;;
        -p|--pass|--password)
            if [[ -z "$2" ]]; then
                echo "Error: Argument for $1 is missing." >&2
                usage
            fi
            FMS_PASS="$2"
            shift 2
            ;;
        -h|--help)
            usage 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$FMS_USER" ]]; then
    echo "Error: The required FileMaker admin username (-u) was not provided." >&2
    usage
fi

if [[ -z "$FMS_PASS" ]]; then
    echo "Error: The required FileMaker admin password (-p) was not provided." >&2
    usage
fi

# Locate fmsadmin binary
if command -v fmsadmin &>/dev/null; then
    FMSADMIN_CMD="fmsadmin"
elif [[ -x "/opt/FileMaker/FileMaker Server/Database Server/bin/fmsadmin" ]]; then
    FMSADMIN_CMD="/opt/FileMaker/FileMaker Server/Database Server/bin/fmsadmin"
elif [[ -x "/usr/local/bin/fmsadmin" ]]; then
    FMSADMIN_CMD="/usr/local/bin/fmsadmin"
else
    echo "Error: fmsadmin command not found. Please ensure FileMaker Server is installed." >&2
    exit 1
fi

# Backoff to 1.5x the previous value in 5 second increments.
backoff() {
    local VALUE=$1
    if [[ $VALUE -lt 10 ]]; then
        VALUE=$((VALUE * 2))
    else
        VALUE=$((((VALUE + (VALUE / 2)) / 5) * 5))
    fi
    echo "$VALUE"
}

# Function to confirm that databases are closed.
db_status() {
    local SLEEP_INTERVAL=10
    local MAX_RETRY=6
    local RETRY_COUNT=0
    local OUTPUT
    local OPEN_DBS
    local STATUS_EXIT

    while true; do
        if ! OUTPUT=$("$FMSADMIN_CMD" list files -s -u "$FMS_USER" -p "$FMS_PASS" 2>&1); then
            # If no files are hosted on the server, fmsadmin reports 10007
            if echo "$OUTPUT" | grep -qiE "10007|no files"; then
                echo "No hosted databases found."
                break
            fi
            echo "Error executing fmsadmin:" >&2
            echo "$OUTPUT" >&2
            exit 1
        fi

        # Explicitly evaluate the Status column
        # - Returns 0 if all databases are strictly "Closed" (or no databases found)
        # - Returns 1 if at least one database is not "Closed"
        # - Returns 2 if unable to locate the "Status" header
        STATUS_EXIT=0
        OPEN_DBS=$(echo "$OUTPUT" | awk '
            NR == 1 {
                status_pos = index($0, "Status")
                if (status_pos == 0) exit 2

                rest = substr($0, status_pos + 6)
                match(rest, /[^ ]/)
                status_len = (RSTART > 0) ? (6 + RSTART - 1) : 0
                next
            }
            /^[[:space:]]*[0-9]+/ {
                db_count++
                stat = (status_len > 0) ? substr($0, status_pos, status_len) : substr($0, status_pos)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", stat)
                split(stat, parts)
                stat = parts[1]

                if (stat != "Closed") {
                    open_count++
                    print "  - ID " $1 ": status is [" stat "]"
                }
            }
            END {
                if (status_pos == 0) exit 2
                if (open_count > 0) exit 1
                exit 0
            }
        ') || STATUS_EXIT=$?

        if [ $STATUS_EXIT -eq 0 ]; then
            echo "All databases are closed."
            break
        elif [ $STATUS_EXIT -eq 2 ]; then
            echo "Error: Could not locate 'Status' column in output:" >&2            echo "$OUTPUT" >&2
            exit 1
        elif [ "$RETRY_COUNT" -ge "$MAX_RETRY" ]; then
            echo "Error: Timed out waiting for databases to close." >&2
            echo "Databases still open or closing:"
            echo "$OPEN_DBS"
            exit 1
        else
            echo "Databases still open or closing:"
            echo "$OPEN_DBS"
            echo "Checking again in ${SLEEP_INTERVAL}s..."
            sleep "$SLEEP_INTERVAL"
            SLEEP_INTERVAL=$(backoff "$SLEEP_INTERVAL")
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done
}

# Gracefully close databases and stop FileMaker Server before performing the upgrade.
echo "Stopping FileMaker Server service..."
"$FMSADMIN_CMD" close -y -u "$FMS_USER" -p "$FMS_PASS" 2>/dev/null || true
db_status
systemctl stop fmshelper 2>/dev/null || true

# Get and install package updates.
# DEBIAN_FRONTEND=noninteractive; don't display interactive menus
# NEEDRESTART_MODE=a; automatically restart services
# Configuration file conflicts:
#   Dpkg::Options::="--force-confdef"; default option when there are no local changes.
#   Dpkg::Options::="--force-confold"; keep the old configuration when there are local changes.

apt-get update

DEBIAN_FRONTEND=noninteractive \
NEEDRESTART_MODE=a \
apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

reboot now