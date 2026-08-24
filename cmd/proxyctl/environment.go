package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

const certificateLifetime = 3650 * 24 * time.Hour

type userMutation int

const (
	userMutationAdd userMutation = iota
	userMutationEnable
	userMutationDisable
	userMutationRotate
	userMutationEnableProtocol
	userMutationDisableProtocol
)

func initEnvironment(args []string) error {
	flags := flag.NewFlagSet("init-environment", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	outputDirectory := flags.String("output-dir", "", "new secret directory")
	sni := flags.String("sni", "", "HY2 certificate SNI")
	name := flags.String("user", "", "initial user name")
	if err := flags.Parse(args); err != nil {
		return errors.New("init-environment arguments are invalid")
	}
	if *outputDirectory == "" || *sni == "" || *name == "" || flags.NArg() != 0 {
		return errors.New("init-environment requires --output-dir, --sni and --user")
	}
	user, err := newUser(*name)
	if err != nil {
		return err
	}
	users := contracts.UsersDocument{Version: 1, Users: []contracts.User{user}}
	if err := users.Validate(); err != nil {
		return err
	}
	usersJSON, err := json.MarshalIndent(users, "", "  ")
	if err != nil {
		return errors.New("users document cannot be encoded")
	}
	realityPrivateKey, err := randomEncoded(32)
	if err != nil {
		return err
	}
	obfsPassword, err := randomEncoded(32)
	if err != nil {
		return err
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

func writeSecretBundle(outputDirectory string, files map[string][]byte) error {
	if _, err := os.Lstat(outputDirectory); !errors.Is(err, os.ErrNotExist) {
		if err == nil {
			return errors.New("secret output directory already exists")
		}
		return errors.New("secret output directory cannot be inspected")
	}
	if err := os.MkdirAll(filepath.Dir(outputDirectory), 0o700); err != nil {
		return errors.New("secret output parent cannot be created")
	}
	if err := os.Mkdir(outputDirectory, 0o700); err != nil {
		return errors.New("secret output directory cannot be created")
	}
	committed := false
	defer func() {
		if !committed {
			_ = os.RemoveAll(outputDirectory)
		}
	}()
	for filename, data := range files {
		if err := writeExclusive(filepath.Join(outputDirectory, filename), data); err != nil {
			return err
		}
	}
	committed = true
	return nil
}

func mutateUser(args []string, mutation userMutation) error {
	command := map[userMutation]string{
		userMutationAdd: "add-user", userMutationEnable: "enable-user",
		userMutationDisable: "disable-user", userMutationRotate: "rotate-user",
		userMutationEnableProtocol: "enable-user-protocol", userMutationDisableProtocol: "disable-user-protocol",
	}[mutation]
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	usersPath := flags.String("users", "", "users JSON path")
	name := flags.String("name", "", "user name")
	protocol := flags.String("protocol", "", "vless or hysteria2")
	if err := flags.Parse(args); err != nil {
		return fmt.Errorf("%s arguments are invalid", command)
	}
	if *usersPath == "" || *name == "" || flags.NArg() != 0 {
		return fmt.Errorf("%s requires --users and --name", command)
	}
	if (mutation == userMutationEnableProtocol || mutation == userMutationDisableProtocol) && *protocol != "vless" && *protocol != "hysteria2" {
		return fmt.Errorf("%s requires --protocol=vless|hysteria2", command)
	}
	info, err := os.Lstat(*usersPath)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("users input must be a regular file")
	}
	data, err := os.ReadFile(*usersPath)
	if err != nil {
		return errors.New("users input cannot be read")
	}
	document, err := contracts.ParseUsers(data)
	if err != nil {
		return err
	}
	index := -1
	for candidate := range document.Users {
		if document.Users[candidate].Name == *name {
			index = candidate
			break
		}
	}
	switch mutation {
	case userMutationAdd:
		if index >= 0 {
			return errors.New("user name already exists")
		}
		user, err := newUser(*name)
		if err != nil {
			return err
		}
		document.Users = append(document.Users, user)
	case userMutationEnable, userMutationDisable, userMutationRotate, userMutationEnableProtocol, userMutationDisableProtocol:
		if index < 0 {
			return errors.New("user name does not exist")
		}
		if mutation == userMutationEnable {
			document.Users[index].Enabled = true
		} else if mutation == userMutationDisable {
			document.Users[index].Enabled = false
		} else if mutation == userMutationRotate {
			rotated, err := newUser(document.Users[index].Name)
			if err != nil {
				return err
			}
			rotated.Enabled = document.Users[index].Enabled
			rotated.Protocols = document.Users[index].Protocols
			document.Users[index] = rotated
		} else if *protocol == "vless" {
			document.Users[index].Protocols.VLESS = mutation == userMutationEnableProtocol
		} else {
			document.Users[index].Protocols.Hysteria2 = mutation == userMutationEnableProtocol
		}
	}
	if err := document.Validate(); err != nil {
		return err
	}
	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return errors.New("users document cannot be encoded")
	}
	return writeFile(*usersPath, append(encoded, '\n'))
}

func newUser(name string) (contracts.User, error) {
	uuid, err := randomUUID()
	if err != nil {
		return contracts.User{}, err
	}
	password, err := randomEncoded(32)
	if err != nil {
		return contracts.User{}, err
	}
	token, err := randomEncoded(32)
	if err != nil {
		return contracts.User{}, err
	}
	return contracts.User{Name: name, Enabled: true, Protocols: contracts.Protocols{VLESS: true, Hysteria2: true}, VLESSUUID: uuid, HY2Password: password, SubscriptionToken: token}, nil
}

func randomEncoded(size int) (string, error) {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return "", errors.New("secure random generation failed")
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func randomUUID() (string, error) {
	data := make([]byte, 16)
	if _, err := rand.Read(data); err != nil {
		return "", errors.New("secure random generation failed")
	}
	data[6] = (data[6] & 0x0f) | 0x40
	data[8] = (data[8] & 0x3f) | 0x80
	encoded := hex.EncodeToString(data)
	return fmt.Sprintf("%s-%s-%s-%s-%s", encoded[:8], encoded[8:12], encoded[12:16], encoded[16:20], encoded[20:]), nil
}

func generateCertificate(sni string, now time.Time) ([]byte, []byte, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, nil, errors.New("HY2 private key generation failed")
	}
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return nil, nil, errors.New("HY2 certificate serial generation failed")
	}
	template := x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: sni},
		DNSNames:     []string{sni},
		NotBefore:    now.Add(-5 * time.Minute),
		NotAfter:     now.Add(certificateLifetime),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		return nil, nil, errors.New("HY2 certificate generation failed")
	}
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, nil, errors.New("HY2 private key encoding failed")
	}
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER}), nil
}

func writeExclusive(path string, data []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		if errors.Is(err, fs.ErrExist) {
			return errors.New("refusing to overwrite a secret file")
		}
		return errors.New("secret file cannot be created")
	}
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return errors.New("secret file cannot be written")
	}
	if err := file.Close(); err != nil {
		return errors.New("secret file cannot be closed")
	}
	return nil
}
