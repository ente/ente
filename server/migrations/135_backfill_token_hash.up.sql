UPDATE tokens
SET token_hash = sha256(convert_to(token, 'UTF8'))
WHERE token_hash IS NULL;
