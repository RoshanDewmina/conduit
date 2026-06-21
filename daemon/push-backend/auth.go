package main

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// authenticatedUser is the only user identity accepted by standard-account
// endpoints. It comes from a verified Supabase access token, never an app
// supplied customer ID or email field.
type authenticatedUser struct {
	ID    string
	Email string
}

type supabaseClaims struct {
	Email string `json:"email"`
	jwt.RegisteredClaims
}

func supabaseJWTConfigured() bool {
	return strings.TrimSpace(os.Getenv("SUPABASE_JWT_SECRET")) != ""
}

func resolveAuthenticatedUser(r *http.Request) (authenticatedUser, error) {
	secret := strings.TrimSpace(os.Getenv("SUPABASE_JWT_SECRET"))
	if secret == "" {
		return authenticatedUser{}, errors.New("standard account authentication is not configured")
	}
	authorization := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(authorization, "Bearer ") {
		return authenticatedUser{}, errors.New("missing bearer token")
	}
	raw := strings.TrimSpace(strings.TrimPrefix(authorization, "Bearer "))
	if raw == "" {
		return authenticatedUser{}, errors.New("missing bearer token")
	}

	claims := &supabaseClaims{}
	options := []jwt.ParserOption{
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithAudience("authenticated"),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(30 * time.Second),
	}
	if issuer := strings.TrimSpace(os.Getenv("SUPABASE_JWT_ISSUER")); issuer != "" {
		options = append(options, jwt.WithIssuer(issuer))
	}
	token, err := jwt.ParseWithClaims(raw, claims, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method %s", token.Method.Alg())
		}
		return []byte(secret), nil
	}, options...)
	if err != nil || !token.Valid || strings.TrimSpace(claims.Subject) == "" {
		return authenticatedUser{}, errors.New("invalid access token")
	}
	return authenticatedUser{ID: claims.Subject, Email: strings.TrimSpace(claims.Email)}, nil
}

func requireAuthenticatedUser(w http.ResponseWriter, r *http.Request) (authenticatedUser, bool) {
	user, err := resolveAuthenticatedUser(r)
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return authenticatedUser{}, false
	}
	return user, true
}
