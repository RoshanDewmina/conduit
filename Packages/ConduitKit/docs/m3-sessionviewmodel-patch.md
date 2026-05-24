# M3 SessionViewModel patch

The following changes need to be applied to `Sources/SessionFeature/SessionViewModel.swift`
after M2 and M3 branches are merged:

1. Add `private var autoReconnectEngine: AutoReconnectEngine?`
2. `public private(set) var tmuxSessionName: String? = nil` (M2 adds a stub for this)
3. After successful connect, start AutoReconnectEngine
4. In connect(), after SSH session established:
   - Try TmuxClient.attachOrCreate(name: "conduit")
   - Store name in tmuxSessionName
   - On reconnect: call TmuxClient.capturePane(name:lastLines:2000), inject as synthetic block
5. `public func handleSceneActive() async` — trigger autoReconnectEngine if status is .suspended
