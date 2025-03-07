#!/bin/bash

# === CONFIGURATION ===
INSTANCE_FILE="instances.lst"  # File containing list of qBittorrent instances
BACKUP_ROOT="./qbittorrent-backups"  # Root backup directory
TORRENT_BACKUP_NAME="torrent-files"  # Directory for storing .torrent files

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

mkdir -p "$BACKUP_ROOT"

# === PROCESS EACH INSTANCE ===
while IFS= read -r LINE; do
    [[ -z "$LINE" || "$LINE" =~ ^#.*$ ]] && continue  # Skip empty lines/comments

    # Extract values (format: NAME URL USERNAME PASSWORD)
    IFS=' ' read -r INSTANCE_NAME QBITTORRENT_URL USERNAME PASSWORD <<< "$LINE"

    echo "Backing up instance: $INSTANCE_NAME ($QBITTORRENT_URL)"

    # Create instance backup directory
    INSTANCE_DIR="$BACKUP_ROOT/$INSTANCE_NAME"
    mkdir -p "$INSTANCE_DIR"

    # Create torrent backup directory
    TORRENT_BACKUP_DIR="$INSTANCE_DIR/$TORRENT_BACKUP_NAME"
    mkdir -p "$TORRENT_BACKUP_DIR"

    # === LOGIN TO QBITTORRENT ===
    COOKIES_FILE=$(mktemp)
    LOGIN_RESPONSE=$(curl -s -c "$COOKIES_FILE" --data "username=$USERNAME&password=$PASSWORD" "$QBITTORRENT_URL/api/v2/auth/login")

    if [[ "$LOGIN_RESPONSE" != "Ok" && "$LOGIN_RESPONSE" != "Ok." ]]; then
        echo "Login failed for $INSTANCE_NAME! Skipping..."
        rm -f "$COOKIES_FILE"
        continue
    fi

    echo "Successfully logged in to $INSTANCE_NAME."

    # === FETCH DATA ===
    TORRENTS=$(curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/torrents/info")
    CATEGORIES=$(curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/torrents/categories")
    TAGS=$(curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/torrents/tags")
    SETTINGS=$(curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/app/preferences")

    # Validate responses
    if [[ -z "$TORRENTS" || -z "$CATEGORIES" || -z "$TAGS" || -z "$SETTINGS" ]]; then
        echo "Error: Failed to retrieve data from API. Skipping instance..."
        rm -f "$COOKIES_FILE"
        continue
    fi

    # === SAVE BACKUP FILE ===
    BACKUP_FILE="$INSTANCE_DIR/backup.json"
    echo "{" > "$BACKUP_FILE"
    echo "\"torrents\": $TORRENTS," >> "$BACKUP_FILE"
    echo "\"categories\": $CATEGORIES," >> "$BACKUP_FILE"
    echo "\"tags\": $TAGS," >> "$BACKUP_FILE"
    echo "\"settings\": $SETTINGS" >> "$BACKUP_FILE"
    echo "}" >> "$BACKUP_FILE"

    echo "Backup saved for $INSTANCE_NAME at $BACKUP_FILE"

    # === BACKUP .TORRENT FILES AND MAGNET LINKS ===
    echo "Downloading .torrent files and magnet links..."
    MAGNETS_FILE="$INSTANCE_DIR/magnets.json"
    echo "[" > "$MAGNETS_FILE"
    FIRST=true

    jq -c '.[]' <<< "$TORRENTS" | while read -r TORRENT; do
        HASH=$(jq -r '.hash' <<< "$TORRENT")
        MAGNET_URI=$(jq -r '.magnet_uri' <<< "$TORRENT")

        # Save .torrent file
        OUTPUT_FILE="$TORRENT_BACKUP_DIR/$HASH.torrent"
        curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/torrents/export?hash=$HASH" -o "$OUTPUT_FILE"

        if [[ -s "$OUTPUT_FILE" ]]; then
            echo "Saved .torrent: $(basename "$OUTPUT_FILE")"
        else
            echo "Failed to save .torrent file for $HASH"
            rm -f "$OUTPUT_FILE"
        fi

        # Save magnet link
        if [[ "$MAGNET_URI" != "null" && "$MAGNET_URI" != "" ]]; then
            [[ "$FIRST" == false ]] && echo "," >> "$MAGNETS_FILE"
            echo "{\"hash\": \"$HASH\", \"magnet\": \"$MAGNET_URI\"}" >> "$MAGNETS_FILE"
            FIRST=false
        fi
    done
    echo "]" >> "$MAGNETS_FILE"

    echo "Magnet links saved to $MAGNETS_FILE"

    # === LOGOUT ===
    curl -s -b "$COOKIES_FILE" "$QBITTORRENT_URL/api/v2/auth/logout" > /dev/null
    rm -f "$COOKIES_FILE"
    echo "Logged out of $INSTANCE_NAME."

done < "$INSTANCE_FILE"

echo "Backup process completed."
