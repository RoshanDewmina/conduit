package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"google.golang.org/api/option"
)

func gcsBucket() string {
	return strings.TrimSpace(os.Getenv("GCS_ARTIFACTS_BUCKET"))
}

func gcsBucketConfigured() bool {
	return gcsBucket() != ""
}

func buildGCSURI(storageRef string) string {
	bucket := gcsBucket()
	if bucket == "" {
		return ""
	}
	ref := strings.TrimPrefix(storageRef, "/")
	return fmt.Sprintf("gs://%s/%s", bucket, ref)
}

// SignedDownloadURL generates a short-lived V4 signed URL for downloading an artifact.
func SignedDownloadURL(ctx context.Context, gcsURI string) (string, error) {
	bucket := gcsBucket()
	if bucket == "" {
		return "", fmt.Errorf("GCS_ARTIFACTS_BUCKET not configured")
	}

	objectName, err := parseGCSObjectName(gcsURI, bucket)
	if err != nil {
		return "", err
	}

	client, err := storage.NewClient(ctx, option.WithScopes("https://www.googleapis.com/auth/devstorage.read_only"))
	if err != nil {
		return "", fmt.Errorf("create GCS client: %w", err)
	}
	defer client.Close()

	url, err := client.Bucket(bucket).SignedURL(objectName, &storage.SignedURLOptions{
		Method:  "GET",
		Expires: time.Now().Add(10 * time.Minute),
		Scheme:  storage.SigningSchemeV4,
	})
	if err != nil {
		return "", fmt.Errorf("sign URL: %w", err)
	}
	return url, nil
}

func parseGCSObjectName(gcsURI, bucket string) (string, error) {
	prefix := fmt.Sprintf("gs://%s/", bucket)
	if len(gcsURI) <= len(prefix) || gcsURI[:len(prefix)] != prefix {
		return "", fmt.Errorf("invalid GCS URI %q for bucket %q", gcsURI, bucket)
	}
	return gcsURI[len(prefix):], nil
}
