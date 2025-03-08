#!/bin/bash

# File containing qBittorrent instance definitions (one per line: INSTANCE_NAME URL USER PASSWORD)
QB_INSTANCES_FILE="instances.lst"

# File containing paths to exclude from untracked files list (recursive exclusion)
EXCLUDE_PATHS_FILE="exclusions.lst"

# Directories
JELLYFIN_DIR="/jellyfin"
DOWNLOADS_DIR="/downloads"
RECYCLE_BIN="/recyclingbin"

# Output file for untracked files
OUTPUT_FILE="untracked-files.txt"

# Temporary files
TEMP_DIR="/tmp/qb-script"
EXISTING_TEMP_DIR=false

> "$OUTPUT_FILE" # Clear the output file

if [ -d "$TEMP_DIR" ]; then
    EXISTING_TEMP_DIR=true
else
    mkdir -p "$TEMP_DIR"
fi

mkdir -p "$RECYCLE_BIN"

# Function to authenticate with qBittorrent and get session cookie
qb_login() {
    local url="$1"
    local user="$2"
    local pass="$3"
    local cookie_file="$4"

    curl -s -X POST --data "username=$user&password=$pass" "$url/api/v2/auth/login" -c "$cookie_file" > /dev/null
}

# Function to get list of files from a qBittorrent instance
get_qbittorrent_files() {
    local url="$1"
    local cookie_file="$2"
    
    curl -s --cookie "$cookie_file" "$url/api/v2/torrents/info" | jq -r '.[].content_path'
}


echo "Mapping $DOWNLOADS_DIR inodes"
# Extract inodes from DOWNLOADS_DIR in one pass
declare -A DOWNLOADS_INODES
while read -r inode; do
    DOWNLOADS_INODES["$inode"]=1
done < <(find "$DOWNLOADS_DIR" -type f -exec stat -c "%i" {} \; | sort -u)


# Check if Jellyfin files exist in DOWNLOADS_DIR
get_jellyfin_hardlinks() {
    find "$JELLYFIN_DIR" -type f -exec stat -c "%i %n" {} \; | while read -r inode file; do
        if [[ -n "${DOWNLOADS_INODES[$inode]}" ]]; then
            echo "$file"
        fi
    done
}

# Build find command with exclusions
EXCLUDE_ARGS=()
if [[ -f "$EXCLUDE_PATHS_FILE" ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && EXCLUDE_ARGS+=("-path" "$DOWNLOADS_DIR/$line" "-prune" "-o")
    done < "$EXCLUDE_PATHS_FILE"
    echo "Excluding: ${EXCLUDE_ARGS[*]}"
fi

pause

echo "Processing $(wc -l < "$QB_INSTANCES_FILE") qBittorrent instances..."
> "$TEMP_DIR/qb-files.txt"  # Empty the file

# Read qBittorrent instances from the file
while IFS=" " read -r instance_name url user pass; do
    if [[ -z "$instance_name" || -z "$url" || -z "$user" || -z "$pass" ]]; then
        continue
    fi

    cookie_file="$TEMP_DIR/$(echo "$url" | md5sum | cut -d ' ' -f1)_cookie.txt"

    echo "[$instance_name] Authenticating with $url..."
    qb_login "$url" "$user" "$pass" "$cookie_file"

    echo "[$instance_name] Fetching files from $url..."
    get_qbittorrent_files "$url" "$cookie_file" >> "$TEMP_DIR/qb-files.txt"
    echo "$(wc -l < "$TEMP_DIR/qb-files.txt") total torrents imported"
done < "$QB_INSTANCES_FILE"

# Sort qBittorrent output
echo "Sorting list of qBittorrent files"
sort -u "$TEMP_DIR/qb-files.txt" -o "$TEMP_DIR/qb-files.txt"

# Get Jellyfin hard-linked files
echo "Finding hardlinked files from $JELLYFIN_DIR"
get_jellyfin_hardlinks > "$TEMP_DIR/jellyfin-files.txt"

# Get all files in /downloads (excluding directories and excluded paths)
echo "Building list of files in $DOWNLOADS_DIR"
find "$DOWNLOADS_DIR" "${EXCLUDE_ARGS[@]}" -type f -print | sort > "$TEMP_DIR/all-files.txt"

# Combine qBittorrent and Jellyfin file lists
echo "Combining output from qBittorrent and $JELLYFIN_DIR"
cat "$TEMP_DIR/qb-files.txt" "$TEMP_DIR/jellyfin-files.txt" | sort | uniq > "$TEMP_DIR/tracked-files.txt"

# Find untracked files
echo "Comparing output from previous step to list of files in $DOWNLOADS_DIR"
comm -23 "$TEMP_DIR/all-files.txt" "$TEMP_DIR/tracked-files.txt" > "$OUTPUT_FILE"

# Count untracked files
UNTRACKED_COUNT=$(wc -l < "$OUTPUT_FILE")

echo "Untracked files saved to $OUTPUT_FILE ($UNTRACKED_COUNT files found)"
if [[ -s "$OUTPUT_FILE" ]]; then
    echo "Choose an action:"
    echo "1) Delete files"
    echo "2) Move files to recycle bin"
    echo "3) Display hard link count of untracked files"
    echo "4) Do nothing"
    read -r choice

    case "$choice" in
        1)
            while IFS= read -r file; do
                rm -v "$file"
                dir=$(dirname "$file")
                while [[ "$dir" != "$DOWNLOADS_DIR" && -d "$dir" && -z "$(find "$dir" -mindepth 1 -type f)" ]]; do
                    rmdir "$dir" && echo "Removed empty directory: $dir"
                    dir=$(dirname "$dir")
                done
            done < "$OUTPUT_FILE"
            echo "Untracked files and empty directories deleted."
            ;;
        2)
            while IFS= read -r file; do
                rel_path="${file#$DOWNLOADS_DIR/}"
                dest="$RECYCLE_BIN/$rel_path"
                mkdir -p "$(dirname "$dest")"
                if ! mv "$file" "$dest"; then
                    echo "Error moving $file to $dest" >&2
                fi
            done < "$OUTPUT_FILE"
            echo "Files moved to recycle bin."
            ;;
        3)
            while IFS= read -r file; do
                link_count=$(stat -c "%h" "$file")
                echo "$file - Hard Links: $link_count"
            done < "$OUTPUT_FILE"
            ;;
        *)
            echo "No action taken."
            ;;
    esac
else
    echo "No untracked files found."
fi

# Cleanup
if [ "$EXISTING_TEMP_DIR" = false ]; then
    rm -rf "$TEMP_DIR"
fi
