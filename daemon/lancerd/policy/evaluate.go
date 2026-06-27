package policy

// Evaluate applies all rules in doc; among matches, strictest effect wins (deny > ask > allow).
// Unmatched requests use doc.Default, or ask when empty (fail-closed).
func Evaluate(doc Document, req Request) Result {
	riskInt := req.Risk
	if riskInt < 0 {
		riskInt = ScoreRiskInt(req.Command, req.Kind)
	}
	riskLabel := RiskLabel(riskInt)
	paths := ExtractPaths(req.Command, req.CWD, "")

	bestRank := 0
	var best Effect
	var matched string

	for i, rule := range doc.Rules {
		if !ruleMatches(rule, req, riskLabel, paths) {
			continue
		}
		e := ParseEffect(rule.Effect)
		r := effectRank(e)
		if r > bestRank {
			bestRank = r
			best = e
			matched = ruleLabel(rule, i)
		}
	}

	if bestRank == 0 {
		def := ParseEffect(doc.Default)
		if doc.Default == "" {
			def = EffectAsk
		}
		return Result{
			Effect:          def,
			MatchedRule:     "default:" + string(def),
			FromDefault:     true,
			ShouldEscalate:  def == EffectAsk,
			ScoredRisk:      riskInt,
			ScoredRiskLabel: riskLabel,
		}
	}

	return Result{
		Effect:          best,
		MatchedRule:     matched,
		FromDefault:     false,
		ShouldEscalate:  best == EffectAsk,
		ScoredRisk:      riskInt,
		ScoredRiskLabel: riskLabel,
	}
}

// EvaluateDocuments merges multiple policy files; strictest effect across all docs wins.
func EvaluateDocuments(docs []Document, req Request) Result {
	if len(docs) == 0 {
		return Evaluate(DefaultDocument(), req)
	}
	merged := Result{
		Effect:          EffectAllow,
		MatchedRule:     "",
		FromDefault:     true,
		ShouldEscalate:  false,
		ScoredRisk:      req.Risk,
		ScoredRiskLabel: RiskLabel(req.Risk),
	}
	bestRank := 0
	for _, doc := range docs {
		res := Evaluate(doc, req)
		if res.ScoredRisk >= 0 {
			merged.ScoredRisk = res.ScoredRisk
			merged.ScoredRiskLabel = res.ScoredRiskLabel
		}
		r := effectRank(res.Effect)
		if r > bestRank {
			bestRank = r
			merged.Effect = res.Effect
			merged.MatchedRule = res.MatchedRule
			merged.FromDefault = res.FromDefault
			merged.ShouldEscalate = res.ShouldEscalate
		}
	}
	if bestRank == 0 {
		return Evaluate(DefaultDocument(), req)
	}
	return merged
}
