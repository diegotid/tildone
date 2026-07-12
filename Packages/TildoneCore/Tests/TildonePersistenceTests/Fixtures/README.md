# Persistence fixture provenance

`TildoneSharedStoreV1` is an actual on-disk SwiftData store generated on
2026-07-13 with Xcode 26.4.1 (build 17E202), the macOS 26.4 SDK, and the
finalized `TildoneSchemaV1` in this Stage 5 hardening pass. Generation used
only the public `TildoneRepository` API with fixed opaque identifiers, dates,
and replica identity. The fixture contains one note, one task, active and
superseded outbox rows, workspace state, and one content-free quarantine row.

The SQLite file SHA-256 is
`a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6`.
Tests copy the fixture to a temporary location before opening it; the checked-in
artifact is never modified in place.

This fixture proves V1 shared-store compatibility through
`TildoneSchemaMigrationPlan`. It is distinct from the released Tildone 1.6.0
legacy-store fixture, whose provenance is recorded in the Stage 5 summary.

`TildoneLegacy160/default.store` is an authentic test-only legacy store
generated from the exact persisted `Todo` and `TodoList` declarations at Git
tag `1.6.0`. Their source SHA-256 values are respectively
`09c6ec936192ecb822e58bf8c5fbc2cfd895429664b60b0a8f532caced42c87e`
and `46f0a44bb635ab610d5e1abe16b69ac36c5d39eaff11ed99b234eeac2039739b`.
The generator compiled those declarations in a temporary Swift package whose
module was named `Tildone`, then wrote through an explicit fixture URL. It did
not resolve, open, copy, or modify the installed app's default store. The
fixture covers a nil task index, duplicate indexes, completed and empty tasks,
Unicode, and an installation-only system note. Its SQLite SHA-256 is
`2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4`.

Stage 6 import/cutover is intentionally absent. Stage 5 treats the legacy
fixture as immutable evidence and never opens it using `TildoneSchemaV1`.
