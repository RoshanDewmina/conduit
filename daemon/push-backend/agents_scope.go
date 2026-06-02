package main

func findAgentForEntitlement(ent subscriptionEntitlement, agentID string) (Agent, bool) {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, agent := range controlPlane.data.Agents {
		if agent.ID != agentID {
			continue
		}
		if resourceVisibleToEntitlement(ent, agent.CustomerID, agent.OrgID) {
			return agent, true
		}
		return Agent{}, false
	}
	return Agent{}, false
}

func findAgentByID(agentID string) (Agent, bool) {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, agent := range controlPlane.data.Agents {
		if agent.ID == agentID {
			return agent, true
		}
	}
	return Agent{}, false
}
