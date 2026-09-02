# Consequential-action undo summary

## Scope

Tildone retains one process-local undo item for the latest eligible local action:

- delete note;
- delete task (including the task's visible subtree on iPhone);
- complete or uncomplete task;
- reorder task or task subtree;
- indent or outdent a task subtree;
- change note color.

Creating content, renaming a note, editing task text, sync transport controls, account/workspace operations, adoption/recovery, and remote changes do not create undo items. A later eligible action replaces the previous item.

## Architecture and persistence behavior

`ConsequentialActionUndoController` lives above `TildoneRepository` and retains only domain identifiers and inverse values in memory. Mac and iPhone application models route eligible actions through this controller; views continue to use snapshots and application-model methods and never access SwiftData or CloudKit objects.

Undo issues ordinary repository mutations. It does not reset versions or modify CloudKit system fields, serialized engine state, tombstones, or pending-mutation rows directly. Explicit note/task restore advances lifecycle versions and schedules normal outbound work. Completion undo restores the prior completion value and every order token changed by completion ordering in one repository structure mutation. Reorder undo restores the exact prior tokens. Mac indentation undo restores prior indentation, subtree order, completion changes caused by hierarchy reconciliation, and installation-local completed-order preferences.

Deleting a note records its visible tasks before deletion. Undo explicitly restores the note and then each retained task, preserving task text, completion, indentation, and order. Deleting a task subtree records and explicitly restores every task in its original order.

## Lifetime and invalidation

The controller is not persisted, so relaunch starts without undo. Closing or replacing an account workspace drops its controller. Mac note-location adoption/recovery transitions explicitly discard undo, as do incompatible/attention sync states. While such an attention state remains active, later local mutations are not retained as undo items.

Remote merges report the stable identities they actually changed. Platform application models discard the current item only when those identities intersect the action's affected records. Remote delivery never registers a new undo item, and an unrelated remote record does not remove the available local undo.

## Platform presentation

On macOS, the standard Edit undo command is replaced with a localized, action-specific title such as “Undo Delete Task”, “Undo Indent Task”, or “Undo Outdent Task”; Command-Z invokes it. The item disappears after a successful undo or required invalidation.

On iPhone, the action is registered with the system undo manager for the standard three-finger swipe. An attached UIKit responder handles shake-to-undo and invokes the same model operation, while yielding first-responder status whenever the keyboard is visible. The notes overview and checklist overflow menus expose the current localized, action-specific Undo command. To avoid announcing routine reversible changes, the brief accessible Undo pill appears only after deleting a note or task; the item remains available from the gestures and menu after that pill disappears. Redo is not retained.

## Verification

Focused deterministic shared-package tests cover:

- note deletion restore, including content, completion, ordering, lifecycle advancement, and attempted outbox supersession;
- task/subtree deletion restore;
- completion and uncompletion with exact order restoration;
- completion undo while an unrelated empty task is concurrently cleaned up;
- reorder token restoration;
- indent/outdent hierarchy, order, and completion restoration, plus Mac completed-order preferences;
- color restoration with a newer local version;
- one-level replacement;
- fresh-controller behavior representing relaunch/workspace replacement;
- explicit attention/workspace invalidation in the iPhone model;
- remote-change exclusion and affected-record invalidation;
- Mac and iPhone action-specific presentation state.

No CloudKit schema, SwiftData migration schema, Production configuration, entitlement, TestFlight, or App Store state is changed by this work.
