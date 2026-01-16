# Bookmark Sync

A bash script to sync bookmarks between Brave Browser and Google Chrome, with Brave bookmarks taking precedence in case of conflicts.

## Requirements

- `jq` (JSON processor) - install with: `sudo apt install jq` (or your package manager)
- Brave Browser installed
- Google Chrome installed

## Usage

1. Make sure both browsers are closed before running the script
2. Make the script executable (if not already):
   ```bash
   chmod +x bookmark_sync.sh
   ```
3. Run the sync script:
   ```bash
   ./bookmark_sync.sh
   ```

## How it works

1. The script reads bookmarks from both Brave and Chrome browsers
2. It merges bookmarks, preferring Brave bookmarks when there are conflicts
3. It creates backups of the original bookmark files before making changes
4. It writes the merged bookmarks back to both browsers

## Backup

The script automatically creates timestamped backups of your bookmark files before making any changes. Backups are saved as:
- `Bookmarks.backup.<timestamp>` in the respective browser directories

## Browser Paths

The script looks for bookmarks at:
- Brave: `~/.config/BraveSoftware/Brave-Browser/Default/Bookmarks`
- Chrome: `~/.config/google-chrome/Default/Bookmarks`

## Important Notes

- **Always close both browsers before running the sync script**
- The script prefers Brave bookmarks in conflicts
- New bookmarks from Chrome will be added to Brave (unless they conflict with existing Brave bookmarks)
- All bookmarks from Brave will be synced to Chrome
