# Storage

## Session Storage

Data tied to the browser tab's lifetime.

The primary information store in session storage is the user's encryption key here. In addition, various other transient bits and bobs are also kept here.

## Local Storage

Data in the local storage is persisted even after the user closes the tab, or the browser itself. This is in contrast with session storage, where the data is cleared when the browser tab is closed.

The data in local storage is tied to the Document's origin (scheme + host).

Some things that get stored here are:

- Details about the logged in user (See: [Note: Accounts DB]).

- Some user preferences (export settings, collection sort order).

> Local storage is not accessible to web workers, so if any non main-thread context needs access to the data, it should be stored in IndexedDB.

## IndexedDB

IndexedDB is a transactional NoSQL store provided by browsers. It has quite large storage limits, and data is stored per origin (and remains persistent across tab restarts).

Unlike local storage, IndexedDB is also accessible from web workers and so we also use IndexedDB for storing ad-hoc key value pairs.

Older code used the LocalForage library for storing things in Indexed DB. This library falls back to localStorage in case Indexed DB storage is not available.

Newer code uses the idb library which provides a promise API over the IndexedDB, but otherwise does not introduce any new abstractions.

For more details, see:

- https://web.dev/articles/indexeddb
- https://github.com/jakearchibald/idb
- https://github.com/localForage/localForage

Some things that get stored here are:

- The collection and file data (See: [Files DB]). Note that the file contents themselves are not stored, only the "EnteFile" object that describes a file.

- Various key value pairs (See: [Note: KV DB]).

## OPFS

OPFS is used for caching entire files when we're running under Electron (the Web Cache API is used in the browser).

As it name suggests, it is an entire file system, private for us ("origin"). In is not undbounded though, and the storage is not guaranteed to be persistent (at least with the APIs we use), hence the cache designation.
