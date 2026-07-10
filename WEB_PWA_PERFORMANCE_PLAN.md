# PM chat Web / PWA Performance Plan

## 1. Current baseline

Production checks on 2026-07-10:

- `index.html`: about 1.5 s total through the public gateway.
- `main.dart.js`: 7.1 MB uncompressed, about 1.8 MB compressed, about 2.4 s transfer.
- `canvaskit.wasm`: 6.9 MB uncompressed, about 2.9 MB compressed, about 2.4 s transfer.
- The active `pmchat_service_worker.js` is push-only and does not cache the app shell.
- The home screen starts chat, contacts, and AI warm-up concurrently.
- The chat list fetches the room page, then enriches every room with multiple detail calls.
- The shared room cache expires after 30 seconds and is memory-only.
- The backend global request limit is 60 requests per minute per client IP.

Observed user-visible consequences:

- Cold Web/PWA startup waits for the full Flutter shell on every process restart.
- Opening the message tab can fan out into dozens or hundreds of requests.
- Enrichment failures are swallowed, leaving `lastMessage` empty and member count at zero.
- Tabs look empty while they refetch even when previously loaded data was available.
- Long chat histories can grow after the first layout pass; this caused initial navigation to land above the newest message. The 2026-07-10 anchoring fix now keeps the first open pinned to the final extent.

## 2. Performance budgets

All optimization work must meet these measurable gates:

| Flow | Target |
| --- | --- |
| Warm PWA launch | useful cached screen in <= 800 ms |
| Cold Fast 3G launch | login or last cached home screen in <= 5 s |
| Message tab initial data | <= 3 API requests before list is usable |
| Contacts initial data | <= 5 API requests before list is usable |
| Open a cached chat | cached messages visible in <= 300 ms |
| Open an uncached chat | newest page visible in <= 2 API requests |
| Five-tab round trip | no 429 and no full-screen loading reset |
| SW update | no mixed-version JS/WASM and no reload loop |

Tests must run at desktop and 390x844 mobile viewports with Fast 3G, Slow 4G, offline-after-warm, and a 250 ms API latency profile.

## 3. Phase P0: collapse request fan-out

### P0.1 Add a room summary endpoint

Add one paginated backend endpoint that returns, for every visible room:

- room identity and type;
- `updatedAt` and the authoritative last message;
- unread count;
- member count and the private-chat peer summary;
- pinned/muted/notification state needed by the list.

The endpoint must enforce the same membership and hidden/blocked rules as the existing room APIs. It should use projections/batched queries, not per-room service calls.

Frontend `getChatRooms()` consumes this response directly. Remove the list-time calls to recent messages, fallback message pages, unread count, members, and notification settings.

Acceptance:

- 100-room account loads the first message page with one summary request.
- The list always has the latest message and member count from the first response.
- Query-count integration test prevents N+1 regressions.

### P0.2 Add in-flight request deduplication

Introduce a keyed request coordinator for chats, contacts, AI lists, profiles, and room messages:

- concurrent callers share one `Future`;
- successful results populate cache once;
- failures do not overwrite last-known-good data;
- cancellation/disposal does not cancel a request still used by another screen.

Change home warm-up policy:

1. Load the visible tab first.
2. After first frame and an idle delay, warm one hidden tab at a time.
3. Skip eager warm-up on slow/offline connections and when data is still fresh.
4. Never start a second warm-up while the visible screen owns the same request.

Acceptance:

- App startup and first chat-list load issue no duplicate room requests.
- Five rapid tab switches stay below the request budget and never return 429.

### P0.3 Persistent stale-while-revalidate data cache

Persist these snapshots in IndexedDB on Web/PWA and the existing local store on native clients:

- room summaries;
- contacts/groups;
- bot/AI lists;
- newest 30-50 messages per room;
- cursors, timestamps, and schema version.

Screens render stale data immediately, then revalidate in the background. Show a small inline stale/offline marker instead of replacing content with a full-screen spinner. Network/decorative-field failures retain cached last messages and member counts.

Invalidate per user and on logout. Add a migration/version field so model changes cannot crash old caches.

Acceptance:

- Relaunch with network offline shows the last cached home and chat history.
- Returning online refreshes data without clearing or reordering the visible list first.
- Logging into a different account cannot see the previous user's cache.

## 4. Phase P1: coherent PWA shell and deployment

### P1.1 Restore app-shell caching safely

Keep Web Push in the existing single `pmchat_service_worker.js`. Add a generated build manifest containing content hashes for the exact release assets.

Caching rules:

- network-first: `index.html`, build manifest, version metadata, SW;
- cache-first by content-hashed release: `main.dart.js`, CanvasKit JS/WASM, fonts, icons, critical assets;
- install a new cache completely before activation;
- activate only when all required assets for one build exist;
- delete old caches after the new release is active;
- preserve one previous complete cache for rollback/recovery.

The cache key must come from generated content hashes, never a hand-maintained constant. Push and `notificationclick` tests remain mandatory.

Acceptance:

- Second launch transfers zero bytes for JS/WASM and boots offline.
- Deploying a new version never serves old JS with new WASM/bootstrap.
- iOS PWA upgrades without manual cache clearing or a reload loop.

### P1.2 Atomic frontend deployment

Stop compiling directly into the directory currently served by nginx. Build into a release directory, validate required files/hashes, then atomically switch a `current` symlink. Retain the previous release for immediate rollback.

Acceptance:

- Concurrent curl loop during deployment never observes a mixed release.
- Rollback is one symlink switch and restores the previous build manifest.

## 5. Phase P2: message loading and rendering

- Initial request returns only the newest page, ordered ascending for display.
- Older history loads only when the user scrolls to the top.
- Delta synchronization requests messages after the newest cached server ID/timestamp.
- WebSocket messages merge by stable message ID and update the room-summary cache.
- Keep the initial-bottom anchor until lazy item extents stabilize, but cancel immediately on a real user drag.
- Preserve per-room scroll position only when the user intentionally left above the bottom; otherwise reopen at latest.

Acceptance:

- 10,000-message room opens with one newest-page request and no full-history transfer.
- Reopening a room that was at the bottom shows the newest message without visible scroll travel.
- Reopening a room intentionally left in history restores that position and shows a “new messages” jump control.

## 6. Phase P3: asset and renderer evaluation

After P0-P2, profile the remaining cold-start cost before changing renderers or frameworks:

- inspect deferred loading opportunities for AI/workspace/call modules;
- remove unused packages and assets proven by size analysis;
- compare current CanvasKit, Flutter Wasm, and any supported lighter renderer using the full UI screenshot suite;
- verify emoji, stickers, video, message bubbles, anonymous effects, and desktop/mobile layouts before accepting a renderer change.

Do not rewrite to native Web yet. Reconsider only if P0-P2 pass and the product still requires a first-ever uncached 1 Mbps visit to become interactive in 1-2 seconds. A rewrite would be a separate product project, not a performance patch.

## 7. Delivery order

1. Room summary endpoint plus frontend adoption.
2. In-flight dedupe and staged warm-up.
3. Persistent stale-while-revalidate cache.
4. Message delta cache and scroll-position rules.
5. Generated app-shell manifest and single SW cache.
6. Atomic release directories.
7. Renderer/bundle experiment only after new production measurements.

Each item ships in an independent commit with backend/frontend tests, a release build, production deployment, request-count capture, and Playwright screenshots. A phase is not complete when only unit tests pass.
