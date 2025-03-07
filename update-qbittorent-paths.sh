#!/bin/bash

# === CONFIGURATION ===
INSTANCE_FILE="instances.lst"  # File containing list of qBittorrent instances
OLD_PATH="/var/lib/qbittorrent-nox/Downloads"  # Old download location

# === CHECK REQUIRED DEPENDENCIES ===
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required but not installed. Please install it first."
    exit 1
fi

# === CHECK INSTANCE FILE ===
if [[ ! -f "$INSTANCE_FILE" ]]; then
    echo "Instance file not found! ($INSTANCE_FILE)"
    exit 1
fi

# === PROCESS EACH INSTANCE ===
while IFS= read -r LINE; do
    [[ -z "LINE"||"LINE" || "LINE" =~ ^#.*$ ]] && continue  # Skip empty lines/comments

    # Extract values (format: NAME URL USERNAME PASSWORD)
    IFS=' ' read -r INSTANCE_NAME QBITTORRENT_URL USERNAME PASSWORD <<< "$LINE"

    echo "Processing instance: INSTANCENAME(INSTANCE_NAME (QBITTORRENT_URL)"

    # === LOGIN TO QBITTORRENT ===
    COOKIES_FILE=$(mktemp)
    LOGIN_RESPONSE=(curl−s−c"(curl -s -c "COOKIES_FILE" --data "username=USERNAME&password=USERNAME&password=PASSWORD" "$QBITTORRENT_URL/api/v2/auth/login")

    if [[ "LOGIN_RESPONSE" != "Ok" && "LOGIN_RESPONSE" != "Ok" && "LOGIN_RESPONSE" != "Ok." ]]; then
        echo "Login failed for $INSTANCE_NAME!"
        rm -f "$COOKIES_FILE"
        continue
    fi

    echo "Successfully logged in to $INSTANCE_NAME."

    # === GET DEFAULT SAVE PATH FROM QBITTORRENT SETTINGS ===
    DEFAULT_SAVE_PATH=(curl -s -b "(curl -s -b "COOKIES_FILE" "$QBITTORRENT_URL/api/v2/app/preferences" | jq -r '.save_path')

    if [[ -z "DEFAULT_SAVE_PATH" || "DEFAULT_SAVE_PATH" || "DEFAULT_SAVE_PATH" == "null" ]]; then
        echo "Failed to get default save path! Skipping instance..."
        curl -s -b "COOKIES_FILE" "COOKIES_FILE" "QBITTORRENT_URL/api/v2/auth/logout" > /dev/null
        rm -f "$COOKIES_FILE"
        continue
    fi

    echo "Default save path for INSTANCE_NAME: INSTANCE_NAME: DEFAULT_SAVE_PATH"

    # === GET ALL TORRENTS ===
    TORRENTS=(curl -s -b "(curl -s -b "COOKIES_FILE" "$QBITTORRENT_URL/api/v2/torrents/info")

    # === PROCESS TORRENTS ===
    jq -c '.[]' <<< "$TORRENTS" | while read -r TORRENT; do
        HASH=(jq -r '.hash' <<< "(jq -r '.hash' <<< "TORRENT")
        SAVE_PATH=(jq -r '.save_path' <<< "(jq -r '.save_path' <<< "TORRENT")
        TORRENT_NAME=(jq -r '.name' <<< "(jq -r '.name' <<< "TORRENT")
        STATUS=(jq -r '.state' <<< "(jq -r '.state' <<< "TORRENT")

        # Skip torrents not in OLD_PATH
        if [[ "SAVE_PATH" != "SAVE_PATH" != "OLD_PATH"* ]]; then
            continue
        fi

        echo "Updating torrent: $TORRENT_NAME"
        echo " - Old path: $SAVE_PATH"
        echo " - New path: $DEFAULT_SAVE_PATH"

        # === BACKUP TORRENT STATUS ===
        if [[ "STATUS" =~ ^(pausedDL|pausedUP|queuedUP|queuedDL)STATUS" =~ ^(pausedDL|pausedUP|queuedUP|queuedDL) ]]; then
            echo "Pausing torrent before moving..."
            curl -s -b "COOKIES_FILE" --data "hashes=COOKIES_FILE" --data "hashes=HASH" "$QBITTORRENT_URL/api/v2/torrents/pause"
            BACKUP_STATUS="paused"
        else
            BACKUP_STATUS="resumed"
        fi

        # === CHANGE TORRENT LOCATION ===
        curl -s -b "COOKIES_FILE" --data "hashes=COOKIES_FILE" --data "hashes=HASH&newLocation=DEFAULT_SAVE_PATH" "DEFAULT_SAVE_PATH" "QBITTORRENT_URL/api/v2/torrents/setLocation"

        # === RESTORE TORRENT STATUS ===
        if [[ "$BACKUP_STATUS" == "resumed" ]]; then
            echo "Resuming torrent after move..."
            curl -s -b "COOKIES_FILE" --data "hashes=COOKIES_FILE" --data "hashes=HASH" "$QBITTORRENT_URL/api/v2/torrents/resume"
        else
            echo "Torrent remains paused."
        fi

        # === FORCE RECHECK ===
        echo "Forcing recheck..."
        curl -s -b "COOKIES_FILE" --data "hashes=COOKIES_FILE" --data "hashes=HASH" "$QBITTORRENT_URL/api/v2/torrents/recheck"
    done

    # === LOGOUT ===
    curl -s -b "COOKIES_FILE" "COOKIES_FILE" "QBITTORRENT_URL/api/v2/auth/logout" > /dev/null
    rm -f "$COOKIES_FILE"
    echo "Logged out of $INSTANCE_NAME."

done < "$INSTANCE_FILE"

echo "Script completed."
