#!/usr/bin/env python3

import sqlite3
import sys
import shutil
import tempfile
import os


def get_columns(cursor):
    cursor.execute("PRAGMA table_info(logins)")
    all_columns = [row[1] for row in cursor.fetchall()]
    return [col for col in all_columns if col != 'id'], all_columns


def delete_empty_passwords(cursor, conn):
    cursor.execute("DELETE FROM logins WHERE username_value IS NULL OR TRIM(username_value) = ''")
    deleted = cursor.rowcount
    conn.commit()
    return deleted


def load_logins(cursor, all_columns):
    cursor.execute("SELECT * FROM logins")
    logins = cursor.fetchall()
    login_map = {}
    for login in logins:
        login_dict = dict(zip(all_columns, login))
        key = (login_dict.get('signon_realm', ''), login_dict.get('username_value', ''))
        login_map[key] = login_dict
    return login_map


def merge_logins(brave_map, chrome_map):
    merged = brave_map.copy()
    for key, login_dict in chrome_map.items():
        if key not in merged:
            merged[key] = login_dict
    return merged


def write_logins(cursor, conn, merged_map, columns):
    cursor.execute("DELETE FROM logins")
    conn.commit()
    
    placeholders = ','.join(['?' for _ in columns])
    insert_sql = "INSERT INTO logins ({}) VALUES ({})".format(','.join(columns), placeholders)
    
    for key, login_dict in merged_map.items():
        values = [login_dict.get(col, None) for col in columns]
        cursor.execute(insert_sql, values)
    
    conn.commit()


def sync_passwords(brave_db, chrome_db):
    temp_chrome = tempfile.NamedTemporaryFile(delete=False)
    temp_brave = tempfile.NamedTemporaryFile(delete=False)
    shutil.copy2(chrome_db, temp_chrome.name)
    shutil.copy2(brave_db, temp_brave.name)

    try:
        conn_brave = sqlite3.connect(temp_brave.name)
        conn_chrome = sqlite3.connect(temp_chrome.name)
        
        cursor_brave = conn_brave.cursor()
        cursor_chrome = conn_chrome.cursor()
        
        columns, all_columns = get_columns(cursor_brave)
        
        deleted_brave = delete_empty_passwords(cursor_brave, conn_brave)
        deleted_chrome = delete_empty_passwords(cursor_chrome, conn_chrome)
        
        if deleted_brave > 0 or deleted_chrome > 0:
            print("  Deleted {} invalid passwords from Brave, {} from Chrome".format(deleted_brave, deleted_chrome))
        
        brave_map = load_logins(cursor_brave, all_columns)
        chrome_map = load_logins(cursor_chrome, all_columns)
        
        merged_map = merge_logins(brave_map, chrome_map)
        
        write_logins(cursor_chrome, conn_chrome, merged_map, columns)
        write_logins(cursor_brave, conn_brave, merged_map, columns)
        
        shutil.copy2(temp_chrome.name, chrome_db)
        shutil.copy2(temp_brave.name, brave_db)
        
        conn_brave.close()
        conn_chrome.close()
        
        os.unlink(temp_chrome.name)
        os.unlink(temp_brave.name)
        
        print("  Synced {} passwords (Brave priority)".format(len(merged_map)))
        
    except Exception as e:
        print("  Error syncing passwords: {}".format(e), file=sys.stderr)
        try:
            os.unlink(temp_chrome.name)
            os.unlink(temp_brave.name)
        except:
            pass
        sys.exit(1)


def main():
    if len(sys.argv) != 3:
        print("Usage: {} <brave_db> <chrome_db>".format(sys.argv[0]), file=sys.stderr)
        sys.exit(1)
    
    brave_db = sys.argv[1]
    chrome_db = sys.argv[2]
    
    if not os.path.exists(brave_db):
        print("Error: Brave database not found: {}".format(brave_db), file=sys.stderr)
        sys.exit(1)
    
    if not os.path.exists(chrome_db):
        print("Error: Chrome database not found: {}".format(chrome_db), file=sys.stderr)
        sys.exit(1)
    
    sync_passwords(brave_db, chrome_db)


if __name__ == "__main__":
    main()
