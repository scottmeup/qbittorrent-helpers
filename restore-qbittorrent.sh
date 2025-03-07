#!/bin/bash

# === CONFIGURATION ===
INSTANCE_FILE="instances.lst"  # File containing list of qBittorrent instances
BACKUP_ROOT="./qbittorrent-backups"  # Root backup directory
TORRENT_BACKUP_NAME="torrent-files"  # Directory containing .torrent files
TORRENT_BACKUP_DIR="$BACKUP_ROOT/$TORRENT_BACKUP_NAME"

# === CHECK REQUIRED DEPENDENCIES ===
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required but not installed. Please install it first."
    exit 1
fi

# === CHECK INSTANCE FILE ===
if [[ ! -f "$INSTANCE_FILE" ]]; then
    echo "Error: Instance file not found! ($INSTANCE_FILE)"
    exit 1
fi

# === PROCESS EACH INSTANCE ===
while IFS= read -r LINE; do
    [[ -z "$LINE" || "$LINE" =~ ^#.*$ ]] && continue  # Skip empty lines/comments

    IFS=' ' read -r INSTANCE_NAME QBITTORRENT_URL USERNAME PASSWORD <<< "$LINE"

    echo "Restoring instance: $INSTANCE_NAME ($QBITTORRENT_URL)"

    INSTANCE_DIR="$BACKUP_ROOT/$INSTANCE_NAME"
    BACKUP_FILE="$INSTANCE_DIR/backup.json"
    MAGNETS_FILE="$INSTANCE_DIR/magnets.json"

    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "No backup found for $INSTANCE_NAME! Skipping..."
        continue
    fi

    # === LOGIN TO QBITTORRENT ===
    COOKIES_FILE=$(mktemp)
    LOGIN_RESPONSE=$(curl -s -c "$COOKIES_FILE" --data "username=$USERNAME&password=$PASSWORD" "$QBITTORRENT_URL/api/v2/auth/login")

    if [[ "$LOGIN_RESPONSE" != "Ok" && "$LOGIN_RESPONSE" != "Ok." ]]; then
        echo "Login failed for $INSTANCE_NAME! Skipping..."
        rm -f "$COOKIES_FILE"
        continue
    fi

    echo "Successfully logged in to $INSTANCE_NAME."

    # === RESTORE SETTINGS, CATEGORIES, TAGS ===
    echo "Restoring settings..."
    curl -s -b "$COOKIES_FILE" --header "Content-Type: application/json" --data "$(jq -c '.settings' "$BACKUP_FILE")" "$QBITTORRENT_URL/api/v2/app/setPreferences"

    echo "Restoring categories..."
    jq -c '.categories | to_entries[]' "$BACKUP_FILE" | while read -r CATEGORY; do
        NAME=$(jq -r '.key' <<< "$CATEGORY")
        SAVE_PATH=$(jq -r '.value.savePath' <<< "$CATEGORY")
        curl -s -b "$COOKIES_FILE" --data "category=$NAME&savePath=$SAVE_PATH" "$QBITTORRENT_URL/api/v2/torrents/createCategory"
    done

    echo "Restoring tags..."
    jq -r '.tags | .[]' "$BACKUP_FILE" | while read -r TAG; do
        curl -s -b "$COOKIES_FILE" --data "tags=$TAG" "$QBITTORRENT_URL/api/v2/torrents/createTags"
    done

    # === RESTORE .TORRENT FILES & MAGNET LINKS ===
    echo "Re-adding torrents..."

    # Restore .torrent files
    if [[ -d "$TORRENT_BACKUP_DIR" ]]; then
        for FILE in "$TORRENT_BACKUP_DIR"/*.torrent; do
            if [[ -f "$FILE" ]]; then
                curl -s -b "$COOKIES_FILE" -F "torrents=@$FILE" "$QBITTORRENT_URL/api/v2/torrents/add"
                echo "Added torrent file: $(basename "$FILE")"
            fi
        done
    else
        echo "No .torrent backup directory found!"
    fi

    # Restore magnet links
    if [[ -f "$MAGNETS_FILE" ]]; then
        jq -c '.[]' "$MAGNETS_FILE" | while read -r ITEM; do
            MAGNET=$(jq -r '.magnet' <<< "$ITEM")
            curl -s -b "$COOKIES_FILE" --data-urlencode "urls=$MAGNET" "$QBITTORRENT_URL/api/v2/torrents/add"
            echo "Added magnet link: ${MAGNET:0:50}..."  # Print first 50 chars for clarity
        done
    else
        echo "No magnet link backup file found!"
    fi

    # === LOGOUT ===
    curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/auth/logout" > /dev/null
    rm -f "$COOKIES_FILE"
    echo "Logged out of $INSTANCE_NAME."

done < "$INSTANCE_FILE"

echo "Restore process completed."
