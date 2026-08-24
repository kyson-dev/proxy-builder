package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

type legacyProductionUser struct {
	Name        *string `json:"name"`
	VLESSUUID   *string `json:"vless_uuid"`
	HY2Password *string `json:"hy2_password"`
	Token       *string `json:"sub_token"`
}

func importLegacyProduction(args []string) error {
	flags := flag.NewFlagSet("import-legacy-production", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	legacyUsersPath := flags.String("legacy-users", "", "legacy users JSON path")
	legacyEnvironmentPath := flags.String("legacy-env", "", "legacy environment file path")
	outputDirectory := flags.String("output-dir", "", "new secret directory")
	sni := flags.String("sni", "", "HY2 certificate SNI")
	renameUser := flags.String("rename-user", "", "legacy_name=new_name")
	if err := flags.Parse(args); err != nil {
		return errors.New("import-legacy-production arguments are invalid")
	}
	if *legacyUsersPath == "" || *legacyEnvironmentPath == "" || *outputDirectory == "" || *sni == "" || *renameUser == "" || flags.NArg() != 0 {
		return errors.New("import-legacy-production requires --legacy-users, --legacy-env, --output-dir, --sni and --rename-user")
	}
	oldName, newName, found := strings.Cut(*renameUser, "=")
	if !found || oldName == "" || newName == "" || strings.Contains(newName, "=") {
		return errors.New("rename-user must be legacy_name=new_name")
	}

	legacyUsers, err := readLegacyProductionUsers(*legacyUsersPath)
	if err != nil {
		return err
	}
	users := make([]contracts.User, 0, len(legacyUsers))
	renamed := 0
	for index, legacy := range legacyUsers {
		if legacy.Name == nil || legacy.VLESSUUID == nil || legacy.HY2Password == nil || legacy.Token == nil {
			return fmt.Errorf("legacy users[%d] has a required field missing", index)
		}
		name := *legacy.Name
		if name == oldName {
			name = newName
			renamed++
		}
		user, err := newUser(name)
		if err != nil {
			return err
		}
		user.VLESSUUID = *legacy.VLESSUUID
		user.SubscriptionToken = *legacy.Token
		users = append(users, user)
	}
	if renamed != 1 {
		return errors.New("legacy user rename must match exactly one user")
	}
	document := contracts.UsersDocument{Version: 1, Users: users}
	if err := document.Validate(); err != nil {
		return err
	}
	usersJSON, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return errors.New("users document cannot be encoded")
	}

	legacyEnvironment, err := readLegacyEnvironment(*legacyEnvironmentPath)
	if err != nil {
		return err
	}
	realityPrivateKey, ok := legacyEnvironment["REALITY_PRIVATE_KEY"]
	if !ok || realityPrivateKey == "" {
		return errors.New("legacy environment is missing REALITY_PRIVATE_KEY")
	}
	obfsPassword, ok := legacyEnvironment["OBFS_PASSWORD"]
	if !ok || obfsPassword == "" {
		return errors.New("legacy environment is missing OBFS_PASSWORD")
	}
	if _, err := contracts.DeriveReality(realityPrivateKey); err != nil {
		return fmt.Errorf("legacy Reality private key: %w", err)
	}
	if len([]byte(obfsPassword)) < 24 {
		return errors.New("legacy obfs password must be at least 24 UTF-8 bytes")
	}
	certificate, certificateKey, err := generateCertificate(*sni, time.Now().UTC())
	if err != nil {
		return err
	}
	if _, err := contracts.InspectCertificate(certificate, certificateKey, *sni, time.Now()); err != nil {
		return err
	}
	return writeSecretBundle(*outputDirectory, map[string][]byte{
		"users.json":          append(usersJSON, '\n'),
		"reality-private-key": []byte(realityPrivateKey),
		"obfs-password":       []byte(obfsPassword),
		"hysteria2.crt":       certificate,
		"hysteria2.key":       certificateKey,
	})
}

func readLegacyProductionUsers(path string) ([]legacyProductionUser, error) {
	data, err := readRegularFile(path, "legacy users input")
	if err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var users []legacyProductionUser
	if err := decoder.Decode(&users); err != nil {
		return nil, errors.New("legacy users input is invalid")
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return nil, errors.New("legacy users input contains a trailing JSON value")
	}
	if len(users) == 0 {
		return nil, errors.New("legacy users input must contain at least one user")
	}
	return users, nil
}

func readLegacyEnvironment(path string) (map[string]string, error) {
	data, err := readRegularFile(path, "legacy environment input")
	if err != nil {
		return nil, err
	}
	values := make(map[string]string)
	for lineNumber, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSuffix(line, "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, found := strings.Cut(line, "=")
		if !found || key == "" || strings.TrimSpace(key) != key {
			return nil, fmt.Errorf("legacy environment input is invalid at line %d", lineNumber+1)
		}
		if _, exists := values[key]; exists {
			return nil, fmt.Errorf("legacy environment input duplicates %s", key)
		}
		values[key] = value
	}
	return values, nil
}

func readRegularFile(path, role string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("%s must be a regular file", role)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("%s cannot be read", role)
	}
	return data, nil
}
