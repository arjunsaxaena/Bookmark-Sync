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

if ! command -v sqlite3 &> /dev/null; then
    echo -e "${RED}Error: sqlite3 is required but not installed.${NC}"
    echo "Install it with: sudo apt install sqlite3 (or your package manager)"
    exit 1
fi

HOME_DIR="$HOME"
BRAVE_PATH="$HOME_DIR/.config/BraveSoftware/Brave-Browser/Default/Bookmarks"
CHROME_PATH="$HOME_DIR/.config/google-chrome/Default/Bookmarks"
BRAVE_PASSWORDS="$HOME_DIR/.config/BraveSoftware/Brave-Browser/Default/Login Data"
CHROME_PASSWORDS="$HOME_DIR/.config/google-chrome/Default/Login Data"

if [ ! -f "$BRAVE_PATH" ]; then
    echo -e "${RED}Error: Brave bookmarks file not found at $BRAVE_PATH${NC}"
    exit 1
fi

if [ ! -f "$CHROME_PATH" ]; then
    echo -e "${RED}Error: Chrome bookmarks file not found at $CHROME_PATH${NC}"
    exit 1
fi

SYNC_PASSWORDS=true
if [ ! -f "$BRAVE_PASSWORDS" ]; then
    echo -e "${YELLOW}Warning: Brave passwords file not found at $BRAVE_PASSWORDS${NC}"
    echo -e "${YELLOW}Password syncing will be skipped.${NC}"
    SYNC_PASSWORDS=false
fi

if [ ! -f "$CHROME_PASSWORDS" ]; then
    echo -e "${YELLOW}Warning: Chrome passwords file not found at $CHROME_PASSWORDS${NC}"
    echo -e "${YELLOW}Password syncing will be skipped.${NC}"
    SYNC_PASSWORDS=false
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

sync_passwords() {
    local brave_db="$1"
    local chrome_db="$2"
    
    if [ ! -f "$brave_db" ] || [ ! -f "$chrome_db" ]; then
        echo -e "${YELLOW}Warning: Cannot sync passwords - database files not accessible${NC}"
        return 1
    fi
    
    if command -v python3 &> /dev/null; then
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local python_script="${script_dir}/sync_passwords.py"
        
        if [ ! -f "$python_script" ]; then
            echo -e "${RED}Error: Python script not found at $python_script${NC}"
            return 1
        fi
        
        python3 "$python_script" "$brave_db" "$chrome_db"
        local python_exit=$?
        if [ $python_exit -ne 0 ]; then
            return 1
        fi
    else
        echo -e "${YELLOW}  Python3 not found, using SQLite-only method (may have limitations)${NC}"
        
        local temp_chrome=$(mktemp)
        local temp_brave=$(mktemp)
        cp "$chrome_db" "$temp_chrome"
        cp "$brave_db" "$temp_brave"
        
        local columns=$(sqlite3 "$temp_chrome" "SELECT GROUP_CONCAT(name, ',') FROM pragma_table_info('logins') WHERE name != 'id';")
        
        sqlite3 "$temp_chrome" << EOF
DELETE FROM logins WHERE username_value IS NULL OR TRIM(username_value) = '';
ATTACH DATABASE '$temp_brave' AS brave_db;
UPDATE logins 
SET password_value = (
    SELECT password_value 
    FROM brave_db.logins 
    WHERE brave_db.logins.signon_realm = logins.signon_realm 
    AND brave_db.logins.username_value = logins.username_value
)
WHERE EXISTS (
    SELECT 1 
    FROM brave_db.logins 
    WHERE brave_db.logins.signon_realm = logins.signon_realm 
    AND brave_db.logins.username_value = logins.username_value
);
INSERT INTO logins ($columns)
SELECT $columns FROM brave_db.logins
WHERE NOT EXISTS (
    SELECT 1 FROM logins 
    WHERE logins.signon_realm = brave_db.logins.signon_realm 
    AND logins.username_value = brave_db.logins.username_value
);
EOF

        sqlite3 "$temp_brave" << EOF
DELETE FROM logins WHERE username_value IS NULL OR TRIM(username_value) = '';
ATTACH DATABASE '$temp_chrome' AS chrome_db;
INSERT INTO logins ($columns)
SELECT $columns FROM chrome_db.logins
WHERE NOT EXISTS (
    SELECT 1 FROM logins 
    WHERE logins.signon_realm = chrome_db.logins.signon_realm 
    AND logins.username_value = chrome_db.logins.username_value
);
EOF

        cp "$temp_chrome" "$chrome_db"
        cp "$temp_brave" "$brave_db"
        rm -f "$temp_chrome" "$temp_brave"
        
        echo "  Password sync completed (using SQLite method)"
    fi
}

main() {
    echo "Loading bookmarks..."

    echo "Creating backups..."
    create_backup "$BRAVE_PATH"
    create_backup "$CHROME_PATH"
    
    if [ "$SYNC_PASSWORDS" = true ]; then
        create_backup "$BRAVE_PASSWORDS"
        create_backup "$CHROME_PASSWORDS"
    fi

    local chrome_backup=$(mktemp)
    local brave_backup=$(mktemp)
    cp "$CHROME_PATH" "$chrome_backup"
    cp "$BRAVE_PATH" "$brave_backup"

    echo "Merging Brave bookmarks into Chrome (preferring Brave in conflicts)..."
    merge_bookmarks "$CHROME_PATH" "$brave_backup" "$chrome_backup"

    echo "Merging original Chrome bookmarks into Brave (Brave takes precedence)..."
    merge_bookmarks "$BRAVE_PATH" "$brave_backup" "$chrome_backup"

    rm -f "$chrome_backup" "$brave_backup"

    if [ "$SYNC_PASSWORDS" = true ]; then
        echo ""
        echo "Syncing passwords (Brave takes priority)..."
        sync_passwords "$BRAVE_PASSWORDS" "$CHROME_PASSWORDS"
        echo -e "${GREEN}Password sync completed!${NC}"
    fi

    echo ""
    echo -e "${GREEN}Bookmark sync completed successfully!${NC}"
    if [ "$SYNC_PASSWORDS" = true ]; then
        echo -e "${GREEN}Password sync completed successfully!${NC}"
    fi
    echo -e "${YELLOW}Note: Close and reopen both browsers to see the changes.${NC}"
}

main
