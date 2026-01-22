# Bookmark & Password Sync

A bash script to sync bookmarks and passwords between Brave Browser and Google Chrome, with Brave data taking precedence in case of conflicts.

## Features

- Syncs bookmarks between Brave and Chrome
- Syncs saved passwords between browsers
- Automatically deletes passwords with no username or email
- Creates timestamped backups before any changes
- Brave data takes priority in conflicts

## Requirements

- `jq` (JSON processor) - install with: `sudo apt install jq`
- `sqlite3` - install with: `sudo apt install sqlite3`
- `python3` (optional, recommended) - install with: `sudo apt install python3`
- Brave Browser installed
- Google Chrome installed

## Usage

1. Make sure both browsers are closed before running the script
2. Make the script executable (if not already):
   ```bash
   chmod +x sync.sh
   ```
3. Run the sync script:
   ```bash
   ./sync.sh
   ```

## How it works

### Bookmarks
1. Reads bookmarks from both Brave and Chrome browsers
2. Merges bookmarks, preferring Brave bookmarks when there are conflicts
3. Creates backups of the original bookmark files before making changes
4. Writes the merged bookmarks back to both browsers

### Passwords
1. Reads saved passwords from both browsers
2. Deletes any passwords with empty or null usernames
3. Merges passwords, preferring Brave passwords when there are conflicts
4. Creates backups of the password databases before making changes
5. Writes the merged passwords back to both browsers

## File Structure

- `sync.sh` - Main bash script for bookmark and password syncing
- `sync_passwords.py` - Python script for password database operations (used if Python 3 is available)
- `sql_queries.sql` - SQL query templates (reference only)

## Backup

The script automatically creates timestamped backups of your bookmark and password files before making any changes. Backups are saved as:
- `Bookmarks.backup.<timestamp>` in the respective browser directories
- `Login Data.backup.<timestamp>` in the respective browser directories

## Browser Paths

The script looks for data at:
- **Brave Bookmarks**: `~/.config/BraveSoftware/Brave-Browser/Default/Bookmarks`
- **Chrome Bookmarks**: `~/.config/google-chrome/Default/Bookmarks`
- **Brave Passwords**: `~/.config/BraveSoftware/Brave-Browser/Default/Login Data`
- **Chrome Passwords**: `~/.config/google-chrome/Default/Login Data`

## Important Notes

- **Always close both browsers before running the sync script**
- The script prefers Brave data (bookmarks and passwords) in conflicts
- New bookmarks/passwords from Chrome will be added to Brave (unless they conflict with existing Brave data)
- All bookmarks/passwords from Brave will be synced to Chrome
- Passwords with no username or email are automatically deleted
- If Python 3 is not available, the script falls back to SQLite-only method (may have limitations)
