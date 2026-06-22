package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"
)

type Org struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type OrgMember struct {
	ID        string `json:"id"`
	OrgID     string `json:"orgId"`
	Email     string `json:"email"`
	Role      string `json:"role"`
	InvitedAt string `json:"invitedAt"`
	Status    string `json:"status"`
}

type inviteMemberRequest struct {
	Email string `json:"email"`
	Role  string `json:"role,omitempty"`
}

type orgsData struct {
	Orgs    []Org       `json:"orgs"`
	Members []OrgMember `json:"members"`
}

var orgsStore = struct {
	path string
}{
	path: dataFilePath("ORGS_FILE", "lancer-orgs.json"),
}

func initOrgsStore() {
	var data orgsData
	if err := loadJSONFile(orgsStore.path, &data); err != nil {
		log.Printf("orgs: load failed: %v", err)
	}
}

func loadOrgsData() (orgsData, error) {
	var data orgsData
	if err := loadJSONFile(orgsStore.path, &data); err != nil {
		return orgsData{}, err
	}
	return data, nil
}

func saveOrgsData(data orgsData) error {
	return saveJSONFile(orgsStore.path, data)
}

func registerOrgRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /orgs/{id}/members", handleListOrgMembers)
	mux.HandleFunc("POST /orgs/{id}/members", handleInviteOrgMember)
}

func handleListOrgMembers(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	orgID := r.PathValue("id")
	if !canAccessOrg(ent, orgID) {
		http.Error(w, "org not found", http.StatusNotFound)
		return
	}

	data, err := loadOrgsData()
	if err != nil {
		http.Error(w, "failed to load org", http.StatusInternalServerError)
		return
	}
	out := make([]OrgMember, 0)
	for _, m := range data.Members {
		if m.OrgID == orgID {
			out = append(out, m)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"members": out})
}

func handleInviteOrgMember(w http.ResponseWriter, r *http.Request) {
	ent, err := resolveEntitlementFromBearer(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusUnauthorized)
		return
	}

	orgID := r.PathValue("id")
	if !canAccessOrg(ent, orgID) {
		http.Error(w, "org not found", http.StatusNotFound)
		return
	}

	var req inviteMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	email := strings.TrimSpace(strings.ToLower(req.Email))
	if email == "" {
		http.Error(w, "email is required", http.StatusBadRequest)
		return
	}
	role := strings.TrimSpace(req.Role)
	if role == "" {
		role = "member"
	}

	member := OrgMember{
		ID:        newResourceID("member"),
		OrgID:     orgID,
		Email:     email,
		Role:      role,
		InvitedAt: time.Now().UTC().Format(time.RFC3339),
		Status:    "invited",
	}

	data, err := loadOrgsData()
	if err != nil {
		http.Error(w, "failed to load org", http.StatusInternalServerError)
		return
	}
	data.Members = append(data.Members, member)
	if err := saveOrgsData(data); err != nil {
		http.Error(w, "failed to persist member", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusCreated, member)
}

func canAccessOrg(ent subscriptionEntitlement, orgID string) bool {
	if orgID == "" {
		return false
	}
	return ent.OrgID == orgID
}

func orgNameForID(orgID string) string {
	if orgID == "" {
		return ""
	}
	data, err := loadOrgsData()
	if err != nil {
		return ""
	}
	for _, org := range data.Orgs {
		if org.ID == orgID {
			return org.Name
		}
	}
	return ""
}

func enrichEntitlementForClient(ent subscriptionEntitlement) subscriptionEntitlement {
	if ent.OrgID == "" {
		return ent
	}
	if ent.OrgName == "" {
		ent.OrgName = orgNameForID(ent.OrgID)
	}
	return ent
}

func resourceVisibleToEntitlement(ent subscriptionEntitlement, customerID, orgID string) bool {
	if customerID != ent.CustomerID {
		return false
	}
	if ent.OrgID == "" {
		return true
	}
	return orgID == "" || orgID == ent.OrgID
}

func setOrgsPath(path string) {
	orgsStore.path = path
}

func resetOrgsForTests() {
	_ = saveJSONFile(orgsStore.path, orgsData{})
}
