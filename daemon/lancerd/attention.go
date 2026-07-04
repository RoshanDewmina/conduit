package main

// pendingGateLaunch records a dispatch/continue/observed/conversation launch
// that was blocked by policy and is waiting for a human approve on the phone.
type pendingGateLaunch struct {
	launchType      string // dispatch | continue | observed | conversation
	argv            []string
	cwd             string
	agent           string
	model           string
	budgetUSD       float64
	runID           string // pre-assigned for conversation-append; prior run for continue
	prompt          string
	vendorSessionID string // observed-continue only
}

// escalateAttention adds a pending approval to the store and fans it out to
// every delivery path (attach client, E2E relay, push-backend). Unlike
// handleHookWithNotify this does NOT block waiting for a decision — dispatch
// gates return needsApproval immediately and resume via maybeLaunchPendingGate.
func (s *server) escalateAttention(event ApprovalEvent, launch *pendingGateLaunch) {
	s.approvals.add(event)

	if launch != nil {
		s.pendingLaunchMu.Lock()
		if s.pendingLaunches == nil {
			s.pendingLaunches = make(map[string]pendingGateLaunch)
		}
		s.pendingLaunches[normID(event.ApprovalID)] = *launch
		s.pendingLaunchMu.Unlock()
	}

	eventCopy := event
	go func() {
		if notification, err := marshalPendingNotification(eventCopy); err == nil {
			s.writeFramed(notification)
		}
	}()
	if s.e2e != nil {
		s.e2e.sendApproval(event)
	}
	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}
}

// maybeLaunchPendingGate launches a run that was held at a dispatch policy gate
// once the human approves the corresponding inbox item.
func (s *server) maybeLaunchPendingGate(event ApprovalEvent, decision string) {
	if decision != "approve" && decision != "approveAlways" {
		return
	}
	s.pendingLaunchMu.Lock()
	launch, ok := s.pendingLaunches[normID(event.ApprovalID)]
	if ok {
		delete(s.pendingLaunches, normID(event.ApprovalID))
	}
	s.pendingLaunchMu.Unlock()
	if !ok {
		return
	}
	s.dispatcher.launchAfterGateApproval(launch, s.auditEntry)
}

// finalizeDispatchGate packages an ask-path dispatch result with the pending event.
func finalizeDispatchGate(event ApprovalEvent, launch pendingGateLaunch, rule string) dispatchResult {
	return dispatchResult{
		Status:        "needsApproval",
		Decision:      "ask",
		Rule:          rule,
		ApprovalID:    event.ApprovalID,
		PendingEvent:  &event,
		PendingLaunch: &launch,
	}
}

// runDispatchResult escalates any pending approval from a dispatch-family call.
func (s *server) runDispatchResult(res dispatchResult) dispatchResult {
	if res.Status == "needsApproval" && res.PendingEvent != nil {
		s.escalateAttention(*res.PendingEvent, res.PendingLaunch)
	}
	return res
}
