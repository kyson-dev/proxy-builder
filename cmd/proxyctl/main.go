package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/kyson-dev/proxy-builder/internal/contracts"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "proxyctl: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		return errors.New("a subcommand is required")
	}
	switch args[0] {
	case "validate-users":
		return validateUsers(args[1:])
	case "validate-release":
		return validateRelease(args[1:])
	case "derive-reality":
		return deriveReality(args[1:])
	case "inspect-certificate":
		return inspectCertificate(args[1:])
	case "inspect-environment":
		return inspectEnvironment(args[1:])
	case "migrate-users":
		return migrateUsers(args[1:])
	case "validate-subscription":
		return validateSubscription(args[1:])
	case "render-sing-box":
		return renderSingBox(args[1:])
	default:
		return errors.New("unknown subcommand")
	}
}

func validateRelease(args []string) error {
	flags := flag.NewFlagSet("validate-release", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	input := flags.String("input", "", "release manifest path")
	if err := flags.Parse(args); err != nil {
		return errors.New("validate-release arguments are invalid")
	}
	if *input == "" || flags.NArg() != 0 {
		return errors.New("validate-release requires --input")
	}
	data, err := os.ReadFile(*input)
	if err != nil {
		return errors.New("release manifest cannot be read")
	}
	_, err = contracts.ParseRelease(data)
	return err
}

func validateUsers(args []string) error {
	flags := flag.NewFlagSet("validate-users", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	input := flags.String("input", "", "users JSON path")
	if err := flags.Parse(args); err != nil {
		return errors.New("validate-users arguments are invalid")
	}
	if *input == "" || flags.NArg() != 0 {
		return errors.New("validate-users requires --input")
	}
	data, err := os.ReadFile(*input)
	if err != nil {
		return errors.New("users input cannot be read")
	}
	_, err = contracts.ParseUsers(data)
	return err
}

func deriveReality(args []string) error {
	flags := flag.NewFlagSet("derive-reality", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	privateKeyFile := flags.String("private-key-file", "", "Reality private key path")
	output := flags.String("output", "", "output JSON path")
	if err := flags.Parse(args); err != nil {
		return errors.New("derive-reality arguments are invalid")
	}
	if *privateKeyFile == "" || *output == "" || flags.NArg() != 0 {
		return errors.New("derive-reality requires --private-key-file and --output")
	}
	privateKey, err := readTrimmed(*privateKeyFile, "Reality private key")
	if err != nil {
		return err
	}
	derived, err := contracts.DeriveReality(privateKey)
	if err != nil {
		return err
	}
	return writeJSON(*output, derived)
}

func inspectCertificate(args []string) error {
	flags := flag.NewFlagSet("inspect-certificate", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	certificatePath := flags.String("cert", "", "certificate path")
	privateKeyPath := flags.String("key", "", "private key path")
	sni := flags.String("sni", "", "expected SNI")
	output := flags.String("output", "", "output JSON path")
	if err := flags.Parse(args); err != nil {
		return errors.New("inspect-certificate arguments are invalid")
	}
	if *certificatePath == "" || *privateKeyPath == "" || *sni == "" || *output == "" || flags.NArg() != 0 {
		return errors.New("inspect-certificate requires --cert, --key, --sni and --output")
	}
	certificatePEM, err := os.ReadFile(*certificatePath)
	if err != nil {
		return errors.New("HY2 certificate cannot be read")
	}
	privateKeyPEM, err := os.ReadFile(*privateKeyPath)
	if err != nil {
		return errors.New("HY2 private key cannot be read")
	}
	inspection, err := contracts.InspectCertificate(certificatePEM, privateKeyPEM, *sni, time.Now())
	if err != nil {
		return err
	}
	return writeJSON(*output, inspection)
}

func renderSingBox(args []string) error {
	flags := flag.NewFlagSet("render-sing-box", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	templatePath := flags.String("template", "", "sing-box template path")
	usersPath := flags.String("users", "", "users JSON path")
	privateKeyPath := flags.String("private-key-file", "", "Reality private key path")
	obfsPasswordPath := flags.String("obfs-password-file", "", "obfs password path")
	releasePath := flags.String("release", "", "release manifest path")
	output := flags.String("output", "", "generated config path")
	if err := flags.Parse(args); err != nil {
		return errors.New("render-sing-box arguments are invalid")
	}
	if *templatePath == "" || *usersPath == "" || *privateKeyPath == "" || *obfsPasswordPath == "" || *releasePath == "" || *output == "" || flags.NArg() != 0 {
		return errors.New("render-sing-box requires all documented path flags")
	}

	templateData, err := os.ReadFile(*templatePath)
	if err != nil {
		return errors.New("sing-box template cannot be read")
	}
	usersData, err := os.ReadFile(*usersPath)
	if err != nil {
		return errors.New("users input cannot be read")
	}
	users, err := contracts.ParseUsers(usersData)
	if err != nil {
		return err
	}
	releaseData, err := os.ReadFile(*releasePath)
	if err != nil {
		return errors.New("release manifest cannot be read")
	}
	release, err := contracts.ParseRelease(releaseData)
	if err != nil {
		return err
	}
	privateKey, err := readTrimmed(*privateKeyPath, "Reality private key")
	if err != nil {
		return err
	}
	obfsPassword, err := readTrimmed(*obfsPasswordPath, "obfs password")
	if err != nil {
		return err
	}
	generated, err := contracts.RenderSingBox(templateData, users, release, privateKey, obfsPassword)
	if err != nil {
		return err
	}
	return writeFile(*output, generated)
}

func readTrimmed(path, role string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("%s cannot be read", role)
	}
	for len(data) > 0 && (data[len(data)-1] == '\n' || data[len(data)-1] == '\r') {
		data = data[:len(data)-1]
	}
	if len(data) == 0 {
		return "", fmt.Errorf("%s is empty", role)
	}
	return string(data), nil
}

func writeJSON(path string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return errors.New("public output cannot be encoded")
	}
	return writeFile(path, append(data, '\n'))
}

func writeFile(path string, data []byte) error {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return errors.New("output directory cannot be created")
	}
	temporary, err := os.CreateTemp(directory, ".proxyctl-*")
	if err != nil {
		return errors.New("temporary output cannot be created")
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return errors.New("temporary output permissions cannot be set")
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return errors.New("output cannot be written")
	}
	if err := temporary.Close(); err != nil {
		return errors.New("output cannot be closed")
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return errors.New("output cannot be committed")
	}
	return nil
}
