---
title: General troubleshooting cases - Self-hosting
description: Fixing various errors when trying to self host Ente
---

# Troubleshooting

## Functionality not working on self hosted instance

If some specific functionality (e.g. album listing, video playback) does not work on your self hosted instance, it is possible that you have set _some_, but not _all_ needed CSP headers (by default, CSP is not enabled).

To expand on it - by default, currently the generated build does not enable CSP headers. The generated build includes a \_headers file that Cloudflare will use to set HTTP response headers, but even these do not enable CSP, it is set to a report only mode.

However, your web server might be setting some CSP policy. If so, then you will need to ensure that all necessary CSP headers are set.

You can see the current [\_headers](https://github.com/ente/ente/blob/main/web/apps/photos/public/_headers) file contents to use a template for your CSP policy. The `Content-Security-Policy-Report-Only` value will show you the CSP headers in "dry run" report-only mode we're setting - you can use that as a template, tweaking it as per your setup.

How do you know if this is the problem you're facing? The browser console _might_ be giving you errors when you try to open the page and perform the corresponding function.

> Refused to load https://subdomain.example.org/... because it does not appear in the script-src directive of the Content Security Policy.

This is not guaranteed, each browsers handles CSP errors differently, and some may silently swallow it.

## Storage not freed after deleting files

Deleted files don't immediately free up S3/MinIO storage:

1. **Trash retention**: 30 days
2. **Deletion queue**: Additional 45 days after permanent deletion
3. **Total**: Up to 75 days before storage is freed

To speed this up:

1. **Empty trash** from the app to skip the 30-day wait
2. **Expedite the deletion queue** via SQL:

    ```sql
    -- Check pending deletions
    SELECT COUNT(*) FROM queue WHERE queue_name = 'deleteObject';

    -- Make items ready for processing (bypasses 45-day safety buffer)
    UPDATE queue
    SET created_at = now_utc_micro_seconds() - (46 * 24 * 60 * 60 * 1000000)
    WHERE queue_name = 'deleteObject';
    ```

The cleanup cron runs every few minutes and will process these items.
