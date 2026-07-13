package main

import "time"

// Liveness/backoff tuning for the E2E relay client (daemon side). These are
// pure constants and pure state machines — kept in their own file so the
// reconnect/keepalive/expired-code logic is unit-testable without a live
// websocket (see e2e_liveness_test.go).
const (
	// e2eKeepalivePingInterval is how often the daemon sends an
	// application-level {"type":"ping"} frame (the underlying
	// golang.org/x/net/websocket library has no RFC6455 control-frame API,
	// so liveness is app-level, matching push-backend's "ping"->"pong"
	// handler in websocket_relay.go).
	e2eKeepalivePingInterval = 30 * time.Second

	// e2eReadTimeout bounds how long the daemon will block on a single
	// websocket.Message.Receive call. Without this, a connection silently
	// dropped by network infra (no FIN/RST — e.g. an idle-connection reap)
	// left Receive blocked forever: the daemon believed it was connected
	// while sitting on a dead socket, and never triggered reconnect. Set to
	// 3x the ping interval so at least two missed ping/pong round-trips
	// elapse before the session is declared dead.
	e2eReadTimeout = 3 * e2eKeepalivePingInterval

	// e2eInitialReconnectBackoff / e2eMaxReconnectBackoff bound the
	// exponential backoff connectLoop uses between redial attempts.
	e2eInitialReconnectBackoff = 1 * time.Second
	e2eMaxReconnectBackoff     = 30 * time.Second

	// e2eMaxExpiredCodeRejections bounds how many consecutive "pairing code
	// expired unconfirmed" rejections the client will silently retry before
	// giving up and surfacing an actionable log line. Without a bound, a
	// dead pairing code retried forever with no operator-visible signal.
	e2eMaxExpiredCodeRejections = 3
)

// nextReconnectBackoff doubles cur, capped at max. Pure so the backoff
// progression is unit-testable without a live socket.
func nextReconnectBackoff(cur, max time.Duration) time.Duration {
	if cur <= 0 {
		return e2eInitialReconnectBackoff
	}
	next := cur * 2
	if next > max {
		return max
	}
	return next
}

// expiredCodeTracker counts consecutive "pairing code expired unconfirmed"
// rejections from the relay across reconnect attempts on the SAME pairing
// code. A dead code must not retry forever silently — after max rejections
// the caller should give up and surface an actionable message rather than
// looping.
type expiredCodeTracker struct {
	streak int
	max    int
}

func newExpiredCodeTracker(max int) *expiredCodeTracker {
	return &expiredCodeTracker{max: max}
}

// record registers one rejection and reports the new streak plus whether the
// tracker has now hit its bound.
func (t *expiredCodeTracker) record() (streak int, exceeded bool) {
	t.streak++
	return t.streak, t.streak >= t.max
}

// reset clears the streak — called on any sign the code is NOT dead (a
// successful pairing).
func (t *expiredCodeTracker) reset() {
	t.streak = 0
}

// expiryAction is what the daemon does in response to a code_expired
// rejection from the relay.
type expiryAction int

const (
	// expiryActionRemint generates a fresh pairing code and reconnects on it.
	expiryActionRemint expiryAction = iota
	// expiryActionReregister keeps the same code+keys and lets connectLoop
	// redial. Used when everConfirmed is true: the backend may have dropped
	// its in-memory PairedAt (Cloud Run cold start) and then aged out a
	// waiting re-registration — reminting would orphan the phone; giving up
	// would leave the laptop offline forever. Same identity re-creates the
	// relay slot on the next dial.
	expiryActionReregister
)

// decideExpiryAction chooses remint vs reregister for a code_expired rejection.
// A code that never completed its first key exchange (everConfirmed==false)
// is provably dead — no phone ever derived a session key on it — so
// re-minting cannot orphan a paired phone. everConfirmed==true (persisted as
// ConfirmedAt in relay-pairing.json) means this code DID complete an exchange
// at least once; never remint it.
func decideExpiryAction(everConfirmed bool) expiryAction {
	if everConfirmed {
		return expiryActionReregister
	}
	return expiryActionRemint
}
