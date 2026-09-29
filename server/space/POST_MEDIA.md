# Post media API

The server stores encrypted assets. Clients choose the codec, resolution, bitrate,
trim range, cover frame, audio settings, and encrypted metadata format. The
10-second video limit is enforced by clients because the server cannot inspect
encrypted video contents.

## Upload and create

Use the existing post upload endpoint with purpose `post` for both covers and
videos. The size limit is 15 MiB (15,728,640 bytes) per encrypted asset, including
encryption overhead. Uploads use `application/octet-stream`. Each Space can have
40 active staged uploads, allowing 20 assets for a ten-video post alongside 20
uploads abandoned by an earlier attempt. Upload URLs last 15 minutes; staged
uploads expire after 30 minutes.

Create a post through the existing endpoint. `objects` contains 1–10 logical
items, with unique positions from 0 through 9. Each item is a photo or a video
cover, with an optional nested `video` asset:

```json
{
  "clientRequestId": "a-stable-id-for-this-publication",
  "encryptedPostKey": "base64-ciphertext",
  "keyVersion": 1,
  "objects": [
    {
      "objectKey": "cover-object-key",
      "position": 0,
      "metadataCipher": "base64-ciphertext",
      "video": {
        "objectKey": "video-object-key",
        "metadataCipher": "base64-ciphertext"
      }
    }
  ]
}
```

The video inherits its parent's position. Nested videos cannot contain another
video. Every asset must have a distinct key, nonempty encrypted metadata, and a
valid staged upload owned by the posting Space. The server verifies uploaded
sizes against the reservations and consumes all reservations atomically when
creating the post. Metadata ciphertext remains opaque, with the existing 6 KiB
decoded limit. Asset sizes in responses come from the verified upload records.

`clientRequestId` is optional for existing clients and limited to 64 bytes.
Clients should generate a fresh ID for each intended publication and retain it
across retries. IDs are scoped to the posting Space. The first successful create
wins; subsequent and overlapping retries return the same post ID without another
post or notification. Reusing an ID does not update the original post. Deleting
the post does not release its ID or allow a retry to recreate it.

## Read and delete

Feed, profile, and individual-post responses use the same nested shape. Photo-only
responses retain their existing shape. Clients that ignore the optional `video`
field can show the cover normally. Covers and videos use the existing authorized
asset download endpoint. Post deletion queues both for cleanup.

## Database and rollout

Migration 148 adds a `role` to post assets, changes position uniqueness to
`(post_id, position, role)`, and stores the optional publication request ID with a
unique index per Space. Existing assets default to `preview`; their ciphertext and
object keys stay unchanged.

Apply the migration and deploy the server throughout the fleet before enabling
video creation in clients. Once deployed, clients can iterate on video processing
and presentation within this contract without further server changes. Rolling
the schema back is blocked while video asset rows exist, since the previous schema
cannot represent both assets at the same position.
