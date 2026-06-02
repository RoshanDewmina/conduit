package main

import (
	"fmt"
	"os"
	"strings"
)

func gcsBucketConfigured() bool {
	return strings.TrimSpace(os.Getenv("GCS_ARTIFACTS_BUCKET")) != ""
}

func buildGCSURI(storageRef string) string {
	bucket := strings.TrimSpace(os.Getenv("GCS_ARTIFACTS_BUCKET"))
	if bucket == "" {
		return ""
	}
	ref := strings.TrimPrefix(storageRef, "/")
	return fmt.Sprintf("gs://%s/%s", bucket, ref)
}
