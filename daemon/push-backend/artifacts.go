package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

type Artifact struct {
	ID          string `json:"id"`
	RunID       string `json:"runId"`
	CustomerID  string `json:"customerId"`
	OrgID       string `json:"orgId,omitempty"`
	Name        string `json:"name"`
	ContentType string `json:"contentType,omitempty"`
	SizeBytes   int64  `json:"sizeBytes,omitempty"`
	StorageRef  string `json:"storageRef"`
	GCSURI      string `json:"gcsUri,omitempty"`
	CreatedAt   string `json:"createdAt"`
}

type createArtifactRequest struct {
	Name        string `json:"name"`
	ContentType string `json:"contentType,omitempty"`
	SizeBytes   int64  `json:"sizeBytes,omitempty"`
	StorageRef  string `json:"storageRef"`
	GCSURI      string `json:"gcsUri,omitempty"`
}

type artifactsData struct {
	Artifacts []Artifact `json:"artifacts"`
}

var artifactsStore = struct {
	path string
}{
	path: dataFilePath("ARTIFACTS_FILE", "conduit-artifacts.json"),
}

func initArtifactsStore() {
	var data artifactsData
	if err := loadJSONFile(artifactsStore.path, &data); err != nil {
		log.Printf("artifacts: load failed: %v", err)
	}
}

func loadArtifactsData() (artifactsData, error) {
	var data artifactsData
	if err := loadJSONFile(artifactsStore.path, &data); err != nil {
		return artifactsData{}, err
	}
	return data, nil
}

func saveArtifactsData(data artifactsData) error {
	return saveJSONFile(artifactsStore.path, data)
}

func registerArtifactRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /runs/{id}/artifacts", handleCreateArtifact)
	mux.HandleFunc("GET /runs/{id}/artifacts", handleListArtifacts)
}

func handleCreateArtifact(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckArtifact); err != nil {
		writeQuotaError(w, err)
		return
	}

	runID := r.PathValue("id")
	if !customerOwnsRun(ent, runID) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}

	var req createArtifactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.Name == "" || req.StorageRef == "" {
		http.Error(w, "name and storageRef are required", http.StatusBadRequest)
		return
	}

	gcsURI := req.GCSURI
	if gcsURI == "" && gcsBucketConfigured() {
		gcsURI = buildGCSURI(req.StorageRef)
	}

	artifact := Artifact{
		ID:          newResourceID("artifact"),
		RunID:       runID,
		CustomerID:  ent.CustomerID,
		OrgID:       ent.OrgID,
		Name:        req.Name,
		ContentType: req.ContentType,
		SizeBytes:   req.SizeBytes,
		StorageRef:  req.StorageRef,
		GCSURI:      gcsURI,
		CreatedAt:   time.Now().UTC().Format(time.RFC3339),
	}

	data, err := loadArtifactsData()
	if err != nil {
		http.Error(w, "failed to load artifacts", http.StatusInternalServerError)
		return
	}
	data.Artifacts = append(data.Artifacts, artifact)
	if err := saveArtifactsData(data); err != nil {
		http.Error(w, "failed to persist artifact", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, artifact)
}

func handleListArtifacts(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	runID := r.PathValue("id")
	if !customerOwnsRun(ent, runID) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}

	data, err := loadArtifactsData()
	if err != nil {
		http.Error(w, "failed to load artifacts", http.StatusInternalServerError)
		return
	}
	out := make([]Artifact, 0)
	for _, a := range data.Artifacts {
		if a.RunID == runID && resourceVisibleToEntitlement(ent, a.CustomerID, a.OrgID) {
			out = append(out, a)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"artifacts": out})
}

func customerOwnsRun(ent subscriptionEntitlement, runID string) bool {
	controlPlane.mu.RLock()
	defer controlPlane.mu.RUnlock()
	for _, run := range controlPlane.data.Runs {
		if run.ID != runID {
			continue
		}
		return resourceVisibleToEntitlement(ent, run.CustomerID, run.OrgID)
	}
	return false
}

func setArtifactsPath(path string) {
	artifactsStore.path = path
}

func resetArtifactsForTests() {
	_ = saveJSONFile(artifactsStore.path, artifactsData{})
}
