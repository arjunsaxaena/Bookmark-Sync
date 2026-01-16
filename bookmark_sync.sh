#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install it with: sudo apt install jq (or your package manager)"
    exit 1
fi

HOME_DIR="$HOME"
BRAVE_PATH="$HOME_DIR/.config/BraveSoftware/Brave-Browser/Default/Bookmarks"
CHROME_PATH="$HOME_DIR/.config/google-chrome/Default/Bookmarks"

if [ ! -f "$BRAVE_PATH" ]; then
    echo -e "${RED}Error: Brave bookmarks file not found at $BRAVE_PATH${NC}"
    exit 1
fi

if [ ! -f "$CHROME_PATH" ]; then
    echo -e "${RED}Error: Chrome bookmarks file not found at $CHROME_PATH${NC}"
    exit 1
fi

create_backup() {
    local file_path="$1"
    local backup_path="${file_path}.backup.$(date +%s)"
    if cp "$file_path" "$backup_path" 2>/dev/null; then
        echo -e "${GREEN}Created backup: $backup_path${NC}"
    else
        echo -e "${YELLOW}Warning: Could not create backup for $file_path${NC}"
    fi
}

merge_bookmarks() {
    local output_file="$1"
    local base_file="$2"
    local additional_file="$3"
    local temp_file=$(mktemp)

    jq '.' "$base_file" > "$temp_file"

    local additional_roots=$(jq -r '.roots | keys[]' "$additional_file")

    for root in $additional_roots; do
        if jq -e ".roots.\"$root\"" "$temp_file" > /dev/null 2>&1; then
            merge_children "$temp_file" "$additional_file" "$root"
        else
            local root_data=$(jq ".roots.\"$root\"" "$additional_file")
            jq ".roots.\"$root\" = $root_data" "$temp_file" > "${temp_file}.tmp"
            mv "${temp_file}.tmp" "$temp_file"
        fi
    done

    local version=$(jq -r '.version' "$base_file")
    local checksum=$(jq -r '.checksum' "$base_file")
    jq ".version = $version | .checksum = \"$checksum\"" "$temp_file" > "${temp_file}.tmp"
    mv "${temp_file}.tmp" "$temp_file"

    cp "$temp_file" "$output_file"
    rm -f "$temp_file" "${temp_file}.tmp"
}

merge_children() {
    local target_file="$1"
    local source_file="$2"
    local root_name="$3"
    local temp_file=$(mktemp)

    cp "$target_file" "$temp_file"

    local target_children=$(jq ".roots.\"$root_name\".children // []" "$temp_file")
    local source_children=$(jq ".roots.\"$root_name\".children // []" "$source_file")

    declare -A target_keys
    local target_count=$(echo "$target_children" | jq 'length')

    for ((i=0; i<target_count; i++)); do
        local child=$(echo "$target_children" | jq ".[$i]")
        local name=$(echo "$child" | jq -r '.name // ""')
        local url=$(echo "$child" | jq -r '.url // ""')
        local type=$(echo "$child" | jq -r '.type // ""')
        local key="$name"

        if [ "$type" = "url" ] && [ -n "$url" ]; then
            key="${url}|${name}"
        fi

        target_keys["$key"]=1
    done

    local source_count=$(echo "$source_children" | jq 'length')

    for ((i=0; i<source_count; i++)); do
        local child=$(echo "$source_children" | jq ".[$i]")
        local name=$(echo "$child" | jq -r '.name // ""')
        local url=$(echo "$child" | jq -r '.url // ""')
        local type=$(echo "$child" | jq -r '.type // ""')
        local key="$name"

        if [ "$type" = "url" ] && [ -n "$url" ]; then
            key="${url}|${name}"
        fi

        if [ -z "${target_keys[$key]}" ]; then
            jq ".roots.\"$root_name\".children += [$child]" "$temp_file" > "${temp_file}.tmp"
            mv "${temp_file}.tmp" "$temp_file"
        fi
    done

    cp "$temp_file" "$target_file"
    rm -f "$temp_file" "${temp_file}.tmp"
}

main() {
    echo "Loading bookmarks..."

    echo "Creating backups..."
    create_backup "$BRAVE_PATH"
    create_backup "$CHROME_PATH"

    local chrome_backup=$(mktemp)
    local brave_backup=$(mktemp)
    cp "$CHROME_PATH" "$chrome_backup"
    cp "$BRAVE_PATH" "$brave_backup"

    echo "Merging Brave bookmarks into Chrome (preferring Brave in conflicts)..."
    merge_bookmarks "$CHROME_PATH" "$brave_backup" "$chrome_backup"

    echo "Merging original Chrome bookmarks into Brave (Brave takes precedence)..."
    merge_bookmarks "$BRAVE_PATH" "$brave_backup" "$chrome_backup"

    rm -f "$chrome_backup" "$brave_backup"

    echo -e "${GREEN}Bookmark sync completed successfully!${NC}"
    echo -e "${YELLOW}Note: Close and reopen both browsers to see the changes.${NC}"
}

main
