package contracts

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	lowerSHA      = regexp.MustCompile(`^[0-9a-f]{40}$`)
	positiveID    = regexp.MustCompile(`^[1-9][0-9]*$`)
	digestImage   = regexp.MustCompile(`^[^[:space:]@]+@sha256:[0-9a-f]{64}$`)
	hostnameLabel = regexp.MustCompile(`^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$`)
)

type Release struct {
	SchemaVersion int    `json:"schema_version"`
	ReleaseID     string `json:"release_id"`
	Environment   string `json:"environment"`
	GitSHA        string `json:"git_sha"`
	DeploymentID  string `json:"deployment_id"`
	SingBoxImage  string `json:"sing_box_image"`
	RealityDest   string `json:"reality_dest"`
	HY2SNI        string `json:"hy2_sni"`
	CreatedAt     string `json:"created_at"`
}

func ParseRelease(data []byte) (Release, error) {
	var release Release
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&release); err != nil {
		return Release{}, errors.New("release manifest JSON is invalid")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return Release{}, errors.New("release manifest contains a trailing JSON value")
	}
	if err := release.Validate(); err != nil {
		return Release{}, err
	}
	return release, nil
}

func (release Release) Validate() error {
	if release.SchemaVersion != 1 {
		return errors.New("release schema_version must equal 1")
	}
	if release.Environment != "development" && release.Environment != "production" {
		return errors.New("release environment must be development or production")
	}
	if !lowerSHA.MatchString(release.GitSHA) {
		return errors.New("release git_sha must be 40 lowercase hexadecimal characters")
	}
	parts := strings.Split(release.DeploymentID, "-")
	if len(parts) != 2 || !positiveID.MatchString(parts[0]) || !positiveID.MatchString(parts[1]) {
		return errors.New("release deployment_id must be <run-id>-<run-attempt>")
	}
	wantedReleaseID := release.GitSHA + "-" + release.DeploymentID
	if release.ReleaseID != wantedReleaseID {
		return errors.New("release release_id does not match git_sha and deployment_id")
	}
	if !digestImage.MatchString(release.SingBoxImage) {
		return errors.New("release sing_box_image must use a sha256 digest")
	}
	if _, _, err := SplitHostPort(release.RealityDest); err != nil {
		return fmt.Errorf("release reality_dest: %w", err)
	}
	if err := ValidateHostname(release.HY2SNI); err != nil {
		return fmt.Errorf("release hy2_sni: %w", err)
	}
	createdAt, err := time.Parse(time.RFC3339, release.CreatedAt)
	if err != nil || !strings.HasSuffix(release.CreatedAt, "Z") || createdAt.Location() != time.UTC {
		return errors.New("release created_at must be RFC3339 UTC ending in Z")
	}
	return nil
}

func SplitHostPort(value string) (string, int, error) {
	host, portText, err := net.SplitHostPort(value)
	if err != nil || host == "" {
		return "", 0, errors.New("must be host:port")
	}
	if net.ParseIP(host) == nil {
		if err := ValidateHostname(host); err != nil {
			return "", 0, errors.New("host is invalid")
		}
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return "", 0, errors.New("port must be between 1 and 65535")
	}
	return host, port, nil
}

func ValidateHostname(value string) error {
	if len(value) < 1 || len(value) > 253 || strings.HasSuffix(value, ".") {
		return errors.New("must be a hostname without a trailing dot")
	}
	for _, label := range strings.Split(value, ".") {
		if !hostnameLabel.MatchString(label) {
			return errors.New("must be a valid hostname")
		}
	}
	return nil
}
