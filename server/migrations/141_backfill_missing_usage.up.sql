INSERT INTO usage(user_id, storage_consumed)
SELECT u.user_id, 0
FROM users u
WHERE NOT EXISTS (
    SELECT 1
    FROM usage us
    WHERE us.user_id = u.user_id
)
ON CONFLICT (user_id) DO NOTHING;
