CREATE UNIQUE INDEX CONCURRENTLY public_file_token_unique_idx
    ON public_file_tokens (access_token) WHERE is_disabled = FALSE;
