# Flutter Web — inspecting local storage safely (read-only)

Use this when PAAX Web shows **"Couldn't start Paax — Some local data on this
device couldn't be read."** It answers *which* local record the app could not
decode without printing user data, auth tokens or any other secret.

What the app keeps in the browser:

| Store | Where | Contents |
|---|---|---|
| Hive boxes (`liked_tracks`, `playlists`, `saved_albums`, `user_profile`, `followed_artists`, `followed_genres`, `settings`, `recent_searches`, `recently_played`, `stream_candidates`, `playlist_ops`, `profile_bootstrap`) | IndexedDB, one database per box, object store `box` | Library cache and sync journal. Binary values are Hive frames prefixed by `0x90 0xA9`, then `typeId + 32`, then the field count. |
| Supabase session | `localStorage` key `sb-<project-ref>-auth-token` | **Secret.** Never print, copy or export it. |

## Snippet (DevTools console, page open on the PAAX origin)

It opens each database read-only and reports, per record, only the adapter
type id, the number of stored fields and the byte length. No field values,
no keys, no `localStorage` values are read.

```js
(async () => {
  const names = (await indexedDB.databases()).map(d => d.name);
  const one = (name) => new Promise((res) => {
    const r = indexedDB.open(name);
    r.onerror = () => res({ name, error: String(r.error) });
    r.onsuccess = () => {
      const db = r.result, out = { name, records: [] };
      if (!db.objectStoreNames.contains('box')) { db.close(); return res(out); }
      const cur = db.transaction('box', 'readonly').objectStore('box').openCursor();
      cur.onsuccess = (e) => {
        const c = e.target.result;
        if (!c) { db.close(); return res(out); }
        const v = c.value;
        if (v instanceof ArrayBuffer || v instanceof Uint8Array) {
          const b = new Uint8Array(v);
          out.records.push({ adapterTypeId: b[2] - 32, numOfFields: b[3], bytes: b.length });
        } else {
          out.records.push({ js: Array.isArray(v) ? 'array' : typeof v });
        }
        c.continue();
      };
    };
  });
  const report = [];
  for (const n of names) report.push(await one(n));
  console.table(report.flatMap(r => (r.records.length ? r.records : [{}]).map(x => ({ box: r.name, ...x }))));
})();
```

Adapter type ids: `0` Track, `1` Playlist, `2` SavedAlbum, `3` UserProfile,
`4` Artist, `5` Genre (see `lib/domain/entities/*.g.dart`).

## Reading the result

* A box that the current build opens but that is **absent** from the list
  means `HiveStorage.init` threw before reaching it (boxes are created on first
  open, in the order listed in `hive_storage.dart`).
* A Track frame with `numOfFields < 11` was written by a build older than
  Phase 3.1 (July 2026). Builds between Phase 3.1 and the `defaultValue`
  fix on field 10 (`isExplicit`) could not decode it (`type 'Null' is not a
  subtype of type 'bool'`). Current builds read it as `isExplicit = false`.

## What NOT to do

* Do not clear site data, IndexedDB or `localStorage` to "fix" the screen: it
  discards the pending-sync journal (`playlist_ops`) and the local library
  cache. The app's own **Sign out** button on that screen is the supported
  escape hatch, and even it keeps the per-account records.
* Do not export the databases: the Hive frames contain the user's library and
  profile, and `localStorage` contains the session token.
