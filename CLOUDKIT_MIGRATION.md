# CloudKit persistence

The app stores clipboard items, folders, folder memberships, chains, wardrobe
items, metadata, embeddings, rich text, and binary assets in the signed-in
user's **private** CloudKit database.

## Xcode / Apple Developer setup

1. Open `hetpaste.xcodeproj`, select the `hetpaste` target, and choose a Team.
2. Under Signing & Capabilities, confirm **iCloud** is present, **CloudKit** is
   checked, and the container is `iCloud.Her.hetpaste`.
3. Register that container for the App ID in the Apple Developer portal if it
   does not already exist. Changing the bundle ID requires changing the
   entitlement's container ID to the registered container.
4. Run a development build while signed into iCloud. CloudKit creates the
   `ClipboardItem`, `ClipboardFolder`, `ClipboardChain`, `ClipboardChainItem`,
   and `WardrobeItem` development record types from the first writes.
5. In the **Development** schema, create `ClipboardAssetChunk` with these
   fields: `parentID` (**String**), `position` (**Int(64)**), `byteCount`
   (**Int(64)**), `createdAt` (**Date/Time**), and `asset` (**Asset**). No
   indexes are required: chunk record names are deterministic, so downloads and
   cleanup never query this type.
6. In CloudKit Console, add sortable indexes for `createdAt` on all record
   types and `position` on `ClipboardChainItem`; add queryable indexes for
   `contextSourceHash` and `chainID`. Deploy the schema to production before
   distributing a production build.
7. Add `thumbnailData` (**Bytes**) to `ClipboardItem`. Leave it unindexed. It
   stores a compact JPEG preview only; the original remains a CloudKit asset.

Stable model UUIDs form every CloudKit record name. Clipboard-to-folder
relationships are UUID arrays so moves survive relaunches. CKAssets hold file,
image, and video payloads. On a server-record conflict, the repository reapplies
the pending model fields to the newest server record (predictable last writer
wins); `updatedAt` is retained for a richer merge policy later.

## Large clipboard payloads

CloudKit regular record fields have a strict size limit. Small binary payloads
and rich text use one CKAsset. Larger content is split into 16 MiB
`ClipboardAssetChunk` CKAssets; the parent `ClipboardItem` stores a compact
manifest containing the chunk count, total bytes, type, and SHA-256 checksum.
The app uploads chunks before committing the parent record, verifies the
checksum after reassembly, uses a metadata preview while content is unloaded,
and removes chunks after card/history deletion or replacement. There is no
50 MB app-level clipboard or sync limit; the practical ceiling is the user's
available iCloud/CloudKit quota and Apple's service limits.

Large transfers run one at a time at background priority. Their completed
chunk positions and local source protection are persisted on disk, so a quit,
crash, or network interruption resumes from the next unfinished chunk. The
Settings → Storage Management screen shows local cache use, current transfer
progress, and lets users clear only unprotected cache files. Startup cleanup
removes chunk uploads whose parent was never committed and whose local source
can no longer be resumed.

## Two-Mac release check

Before deploying Production, sign both Macs into the same Apple ID and run a
Development build on each. On Mac A, copy a file larger than 50 MB and wait for
Settings → iCloud Library to return to “iCloud synced.” On Mac B, reopen the
app, wait for the card metadata, then copy/restore the card and compare its
size or checksum with the original. Delete the card on Mac A, sync, then
reopen Mac B and confirm that both the card and its local cached copy disappear.
