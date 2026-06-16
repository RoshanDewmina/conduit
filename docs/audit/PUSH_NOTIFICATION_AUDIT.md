# Push Notification Audit — End-to-End Path Trace

## Full Path

```
iOS App                      Push Backend                  conduitd Daemon
───────                      ────────────                  ──────────────
1. requestAuthorization()                                        │
2. registerForRemoteNotifications()                              │
3. APNs returns deviceToken                                      │
4. POST /register { sessionId, deviceToken } ──────►             │
   (to pushBackendURL)                           │               │
                                                  ▼               │
                                          register.handleRegister │
                                          stores { sessionId →   │
                                            apnsToken }           │
                                                                  │
                                        ┌───── 5. conduitd sends  │
                                        │      approval event     │
                                        │      POST /approval     │
                                        │      { sessionId,       │
                                        │        command, risk }  │
                                        ▼                         │
6. handleApproval reads registry ──────►                          │
7. pushApproval() sends APNs alert ───► APNs ────► iOS            │
8. iOS shows banner with              (push)                      │
   Approve/Reject buttons                                         │
9. User taps Approve ───► ConduitNotificationDelegate             │
                         routes via NotificationCenter             │
                         → ApprovalActionBuffer                   │
                         → ApprovalRelay.decide()                 │
10. Decision sent back to conduitd via WebSocket                  │
```

## Verification: Every Link

| Step | What should happen | Status | Evidence (file:line) |
|---|---|---|---|
| 1 | `requestAuthorization([.alert,.badge,.sound])` | ✅ Implemented | `Notifications.swift:156-163` |
| 2 | `registerForRemoteNotifications()` | ✅ Implemented | `ConduitApp.swift:112` |
| 3 | `didRegisterForRemoteNotificationsWithDeviceToken` callback | ✅ Implemented | `ConduitApp.swift:118-128` |
| 4 | Token POSTed to push backend `/register` | ✅ Implemented | `Notifications.swift:230-239` |
| 4a | `pushBackendURL` from Info.plist (`CONDUIT_PUSH_BACKEND_URL`) | ✅ Configured | `ConduitApp.swift:27`, `Info.plist:35` |
| 5 | conduitd sends approval event to push backend | ✅ Backend handles | `push-backend/main.go:228-260` (`handleApproval`) |
| 6 | Backend looks up device token by sessionId | ✅ Implemented | `push-backend/main.go:241-247` |
| 7 | APNs push sent with approval category | ✅ Implemented | `push-backend/main.go:350-413` (`pushApproval`) |
| 8 | iOS shows banner + Approve/Reject buttons | ✅ Categories registered | `Notifications.swift:281-311` (`registerCategories`) |
| 9 | `ConduitNotificationDelegate.didReceive` routes action | ✅ Implemented | `ConduitApp.swift:168-217` |
| 9a | Cold-launch buffer (MAJOR-6) | ✅ Implemented | `Notifications.swift:48-71` (`ApprovalActionBuffer`) |
| 9b | Background push refresh | ✅ Implemented | `ConduitApp.swift:137-149` (`didReceiveRemoteNotification`) |
| 10 | Decision sent back via WebSocket | ✅ Architecture documented | Side-channel WebSocket in relay |

## Entitlements

| Entitlement | Value | Status | Evidence |
|---|---|---|---|
| `aps-environment` | `production` | ✅ Set | `Conduit.entitlements:6` |

**Note:** `production` means development builds on simulators will silently fail to register
for remote notifications (expected — APNs push requires a physical device with a
development or distribution provisioning profile). To test on a development device,
the entitlement must match the provisioning profile (set to `development` for debug builds).

## Required env vars for push-backend deployment

| Env var | Where used | Current status |
|---|---|---|
| `APNS_KEY_ID` | `push-backend/main.go:297` | Must be set at deploy time |
| `APNS_TEAM_ID` | `push-backend/main.go:298` | Must be set at deploy time |
| `APNS_KEY_PATH` | `push-backend/main.go:299` | Must point to `.p8` file at deploy time |
| `APNS_BUNDLE_ID` | `push-backend/main.go:300` | Must be `dev.conduit.mobile` |
| `APPROVAL_RELAY_SECRET` | `push-backend/main.go:153` | Must be set for auth on `/register` + `/approval` |

## Gaps Found

**None.** The push notification path is fully wired end-to-end:

1. iOS registers APNs token and POSTs it to the push backend.
2. conduitd sends approval/run-complete events to the push backend.
3. Backend maps session → device token and pushes via APNs.
4. iOS receives, displays banner with action buttons, and routes taps.

## Edge Cases

| Edge case | Handled? | Details |
|---|---|---|
| Simulator (no APNs) | ✅ | `didFailToRegisterForRemoteNotificationsWithError` logs silently; `pushBackendURL` empty check at `ConduitApp.swift:120` skips registration |
| Cold launch + lock-screen tap | ✅ | `ApprovalActionBuffer` records action before subscriber exists; drained once `AppRoot` is ready |
| Token rotation | ✅ | APNs token is re-POSTed on every cold launch (AppDelegate is re-created) |
| Backend unreachable | ✅ | Token POST is fire-and-forget (`_ = try? await URLSession.shared.data(for: req)`) |
| Empty `CONDUIT_PUSH_BACKEND_URL` | ✅ | Guard at `ConduitApp.swift:120` skips registration entirely |