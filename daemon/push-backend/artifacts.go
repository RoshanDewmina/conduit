package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
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
	path: dataFilePath("ARTIFACTS_FILE", "lancer-artifacts.json"),
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
	mux.HandleFunc("DELETE /runs/{id}/artifacts/{artifactId}", handleDeleteArtifact)
	mux.HandleFunc("GET /runs/{id}/artifacts/{artifactId}/download", handleArtifactDownload)
}

func handleCreateArtifact(w http.ResponseWriter, r *http.Request) {
	runID := r.PathValue("id")

	// Try runner-token auth first (runner uploading artifacts for its own run).
	if runTokenID, ok := resolveRunFromRunnerToken(r); ok && runTokenID == runID {
		handleCreateArtifactAsRunner(w, r, runID)
		return
	}

	// Fall back to app entitlement auth.
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	if err := enforceQuota(ent, quotaCheckArtifact); err != nil {
		writeQuotaError(w, err)
		return
	}

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

// handleCreateArtifactAsRunner handles artifact creation authenticated via a
// runner token — used by cloud runners uploading outputs for their own run.
func handleCreateArtifactAsRunner(w http.ResponseWriter, r *http.Request, runID string) {
	// Look up the run to get customerID / orgID.
	var customerID, orgID string
	controlPlane.mu.RLock()
	for _, run := range controlPlane.data.Runs {
		if run.ID == runID {
			customerID = run.CustomerID
			orgID = run.OrgID
			break
		}
	}
	controlPlane.mu.RUnlock()

	if customerID == "" {
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
	// Validate that the runner-supplied GCSURI actually belongs to this run.
	// Prevents a compromised runner from registering a URI pointing to another run's data.
	if gcsURI != "" && gcsBucketConfigured() {
		objName, err := parseGCSObjectName(gcsURI, gcsBucket())
		if err != nil || !strings.HasPrefix(objName, "runs/"+runID+"/") {
			http.Error(w, "forbidden: gcsUri must reference this run", http.StatusForbidden)
			return
		}
	}

	artifact := Artifact{
		ID:          newResourceID("artifact"),
		RunID:       runID,
		CustomerID:  customerID,
		OrgID:       orgID,
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
		http.Error(w, "failed to save artifact", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, artifact)
}

// handleArtifactDownload returns a short-lived signed GCS download URL for an artifact.
func handleArtifactDownload(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	runID := r.PathValue("id")
	artifactID := r.PathValue("artifactId")

	if !customerOwnsRun(ent, runID) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}

	data, err := loadArtifactsData()
	if err != nil {
		http.Error(w, "failed to load artifacts", http.StatusInternalServerError)
		return
	}

	var artifact *Artifact
	for i := range data.Artifacts {
		a := &data.Artifacts[i]
		if a.ID == artifactID && a.RunID == runID && resourceVisibleToEntitlement(ent, a.CustomerID, a.OrgID) {
			artifact = a
			break
		}
	}
	if artifact == nil {
		http.Error(w, "artifact not found", http.StatusNotFound)
		return
	}

	if artifact.GCSURI == "" {
		http.Error(w, "artifact has no GCS URI; use SFTP for ssh-host artifacts", http.StatusBadRequest)
		return
	}
	// Defense-in-depth: verify the stored URI belongs to this run before signing.
	if bucket := gcsBucket(); bucket != "" {
		objName, err := parseGCSObjectName(artifact.GCSURI, bucket)
		if err != nil || !strings.HasPrefix(objName, "runs/"+runID+"/") {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
	}

	signedURL, err := SignedDownloadURL(r.Context(), artifact.GCSURI)
	if err != nil {
		http.Error(w, "failed to generate download URL: "+err.Error(), http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"url": signedURL})
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

func handleDeleteArtifact(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}
	runID := r.PathValue("id")
	artifactID := r.PathValue("artifactId")
	if !customerOwnsRun(ent, runID) {
		http.Error(w, "run not found", http.StatusNotFound)
		return
	}
	data, err := loadArtifactsData()
	if err != nil {
		http.Error(w, "failed to load artifacts", http.StatusInternalServerError)
		return
	}
	idx := -1
	for i := range data.Artifacts {
		a := data.Artifacts[i]
		if a.ID == artifactID && a.RunID == runID && resourceVisibleToEntitlement(ent, a.CustomerID, a.OrgID) {
			idx = i
			break
		}
	}
	if idx == -1 {
		http.Error(w, "artifact not found", http.StatusNotFound)
		return
	}
	data.Artifacts = append(data.Artifacts[:idx], data.Artifacts[idx+1:]...)
	if err := saveArtifactsData(data); err != nil {
		http.Error(w, "failed to persist artifacts", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
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
