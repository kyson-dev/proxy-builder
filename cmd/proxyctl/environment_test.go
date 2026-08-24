package main

import (
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

func TestInitEnvironmentCreatesValidatedPrivateBundle(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "development")
	if err := initEnvironment([]string{"--output-dir", directory, "--sni", "www.example.com", "--user", "alice"}); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(directory)
	if err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("secret directory mode = %v, err = %v", info.Mode().Perm(), err)
	}
	for _, name := range []string{"users.json", "reality-private-key", "obfs-password", "hysteria2.crt", "hysteria2.key"} {
		info, err := os.Stat(filepath.Join(directory, name))
		if err != nil || info.Mode().Perm() != 0o600 {
			t.Fatalf("%s mode = %v, err = %v", name, info.Mode().Perm(), err)
		}
	}
	usersData, _ := os.ReadFile(filepath.Join(directory, "users.json"))
	document, err := contracts.ParseUsers(usersData)
	if err != nil || len(document.Users) != 1 || document.Users[0].Name != "alice" || !document.Users[0].Enabled {
		t.Fatalf("unexpected users: %#v, err = %v", document, err)
	}
	privateKey, _ := readTrimmed(filepath.Join(directory, "reality-private-key"), "Reality private key")
	if _, err := contracts.DeriveReality(privateKey); err != nil {
		t.Fatal(err)
	}
	certPEM, _ := os.ReadFile(filepath.Join(directory, "hysteria2.crt"))
	keyPEM, _ := os.ReadFile(filepath.Join(directory, "hysteria2.key"))
	if _, err := contracts.InspectCertificate(certPEM, keyPEM, "www.example.com", time.Now()); err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(certPEM)
	certificate, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	want := 3650 * 24 * time.Hour
	if lifetime := certificate.NotAfter.Sub(certificate.NotBefore); lifetime < want || lifetime > want+10*time.Minute {
		t.Fatalf("certificate lifetime = %s", lifetime)
	}
	if err := initEnvironment([]string{"--output-dir", directory, "--sni", "www.example.com", "--user", "bob"}); err == nil {
		t.Fatal("initEnvironment overwrote an existing bundle")
	}
}

func TestUserLifecycleUsesImmediateCredentialRotation(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "development")
	if err := initEnvironment([]string{"--output-dir", directory, "--sni", "www.example.com", "--user", "alice"}); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "users.json")
	if err := mutateUser([]string{"--users", path, "--name", "bob"}, userMutationAdd); err != nil {
		t.Fatal(err)
	}
	before := readUsersForTest(t, path)
	if err := mutateUser([]string{"--users", path, "--name", "alice"}, userMutationRotate); err != nil {
		t.Fatal(err)
	}
	after := readUsersForTest(t, path)
	if before.Users[0].VLESSUUID == after.Users[0].VLESSUUID || before.Users[0].HY2Password == after.Users[0].HY2Password || before.Users[0].SubscriptionToken == after.Users[0].SubscriptionToken {
		t.Fatal("rotate-user did not replace every credential")
	}
	if err := mutateUser([]string{"--users", path, "--name", "bob"}, userMutationDisable); err != nil {
		t.Fatal(err)
	}
	disabled := readUsersForTest(t, path)
	if disabled.Users[1].Enabled {
		t.Fatal("disable-user left the user enabled")
	}
	if err := mutateUser([]string{"--users", path, "--name", "bob"}, userMutationEnable); err != nil {
		t.Fatal(err)
	}
	if !readUsersForTest(t, path).Users[1].Enabled {
		t.Fatal("enable-user left the user disabled")
	}
}

func TestUserLifecycleRejectsDisablingLastEnabledUserAndSymlink(t *testing.T) {
	directory := filepath.Join(t.TempDir(), "development")
	if err := initEnvironment([]string{"--output-dir", directory, "--sni", "www.example.com", "--user", "alice"}); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "users.json")
	before, _ := os.ReadFile(path)
	if err := mutateUser([]string{"--users", path, "--name", "alice"}, userMutationDisable); err == nil {
		t.Fatal("disable-user accepted a document without enabled users")
	}
	after, _ := os.ReadFile(path)
	if string(before) != string(after) {
		t.Fatal("failed mutation changed users.json")
	}
	symlink := filepath.Join(t.TempDir(), "users.json")
	if err := os.Symlink(path, symlink); err != nil {
		t.Fatal(err)
	}
	if err := mutateUser([]string{"--users", symlink, "--name", "bob"}, userMutationAdd); err == nil {
		t.Fatal("add-user accepted a symbolic link")
	}
}

func readUsersForTest(t *testing.T, path string) contracts.UsersDocument {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	document, err := contracts.ParseUsers(data)
	if err != nil {
		t.Fatal(err)
	}
	return document
}
