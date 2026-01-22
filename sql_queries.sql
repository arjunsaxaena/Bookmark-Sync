ATTACH DATABASE '{brave_db}' AS brave_db;
ATTACH DATABASE '{chrome_db}' AS chrome_db;

DELETE FROM logins WHERE username_value IS NULL OR TRIM(username_value) = '';

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

INSERT INTO logins ({columns})
SELECT {columns} FROM brave_db.logins
WHERE NOT EXISTS (
    SELECT 1 FROM logins 
    WHERE logins.signon_realm = brave_db.logins.signon_realm 
    AND logins.username_value = brave_db.logins.username_value
);

INSERT INTO logins ({columns})
SELECT {columns} FROM chrome_db.logins
WHERE NOT EXISTS (
    SELECT 1 FROM logins 
    WHERE logins.signon_realm = chrome_db.logins.signon_realm 
    AND logins.username_value = chrome_db.logins.username_value
);
