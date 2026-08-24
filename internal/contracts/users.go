package contracts

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

var canonicalUUID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type User struct {
	Name              string    `json:"name"`
	Enabled           bool      `json:"enabled"`
	Protocols         Protocols `json:"protocols"`
	VLESSUUID         string    `json:"vless_uuid"`
	HY2Password       string    `json:"hy2_password"`
	SubscriptionToken string    `json:"subscription_token"`
}

type Protocols struct {
	VLESS     bool `json:"vless"`
	Hysteria2 bool `json:"hysteria2"`
}

type UsersDocument struct {
	Version int    `json:"version"`
	Users   []User `json:"users"`
}

func ParseUsers(data []byte) (UsersDocument, error) {
	type userWire struct {
		Name      *string `json:"name"`
		Enabled   *bool   `json:"enabled"`
		Protocols *struct {
			VLESS     *bool `json:"vless"`
			Hysteria2 *bool `json:"hysteria2"`
		} `json:"protocols"`
		VLESSUUID         *string `json:"vless_uuid"`
		HY2Password       *string `json:"hy2_password"`
		SubscriptionToken *string `json:"subscription_token"`
	}
	type documentWire struct {
		Version *int        `json:"version"`
		Users   *[]userWire `json:"users"`
	}

	var wire documentWire
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&wire); err != nil {
		return UsersDocument{}, fmt.Errorf("users document is invalid: %w", sanitizeJSONError(err))
	}
	if err := ensureJSONEOF(decoder); err != nil {
		return UsersDocument{}, err
	}
	if wire.Version == nil {
		return UsersDocument{}, errors.New("field \"version\" is required")
	}
	if wire.Users == nil {
		return UsersDocument{}, errors.New("field \"users\" is required")
	}
	document := UsersDocument{Version: *wire.Version, Users: make([]User, 0, len(*wire.Users))}
	for index, user := range *wire.Users {
		prefix := fmt.Sprintf("users[%d]", index)
		if user.Name == nil {
			return UsersDocument{}, fmt.Errorf("%s.name is required", prefix)
		}
		if user.Enabled == nil {
			return UsersDocument{}, fmt.Errorf("%s.enabled is required", prefix)
		}
		if user.VLESSUUID == nil {
			return UsersDocument{}, fmt.Errorf("%s.vless_uuid is required", prefix)
		}
		if user.HY2Password == nil {
			return UsersDocument{}, fmt.Errorf("%s.hy2_password is required", prefix)
		}
		if user.SubscriptionToken == nil {
			return UsersDocument{}, fmt.Errorf("%s.subscription_token is required", prefix)
		}
		protocols := Protocols{VLESS: true, Hysteria2: true}
		if user.Protocols != nil {
			if user.Protocols.VLESS == nil {
				return UsersDocument{}, fmt.Errorf("%s.protocols.vless is required", prefix)
			}
			if user.Protocols.Hysteria2 == nil {
				return UsersDocument{}, fmt.Errorf("%s.protocols.hysteria2 is required", prefix)
			}
			protocols = Protocols{VLESS: *user.Protocols.VLESS, Hysteria2: *user.Protocols.Hysteria2}
		}
		document.Users = append(document.Users, User{
			Name:              *user.Name,
			Enabled:           *user.Enabled,
			Protocols:         protocols,
			VLESSUUID:         *user.VLESSUUID,
			HY2Password:       *user.HY2Password,
			SubscriptionToken: *user.SubscriptionToken,
		})
	}
	if err := document.Validate(); err != nil {
		return UsersDocument{}, err
	}
	return document, nil
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		return errors.New("users document contains a trailing JSON value")
	}
	return nil
}

func sanitizeJSONError(err error) error {
	var syntaxError *json.SyntaxError
	if errors.As(err, &syntaxError) {
		return fmt.Errorf("JSON syntax error at byte %d", syntaxError.Offset)
	}
	var typeError *json.UnmarshalTypeError
	if errors.As(err, &typeError) {
		return fmt.Errorf("field %q has the wrong JSON type", typeError.Field)
	}
	message := err.Error()
	if strings.HasPrefix(message, "json: unknown field ") {
		return errors.New(message)
	}
	return errors.New("JSON cannot be decoded")
}

func (document UsersDocument) Validate() error {
	if document.Version != 1 {
		return errors.New("field \"version\" must equal 1")
	}
	if len(document.Users) == 0 {
		return errors.New("field \"users\" must contain at least one user")
	}

	names := make(map[string]struct{}, len(document.Users))
	uuids := make(map[string]struct{}, len(document.Users))
	passwords := make(map[string]struct{}, len(document.Users))
	tokens := make(map[string]struct{}, len(document.Users))
	enabled := 0

	for index, user := range document.Users {
		prefix := fmt.Sprintf("users[%d]", index)
		if err := validateName(user.Name); err != nil {
			return fmt.Errorf("%s.name: %w", prefix, err)
		}
		if !canonicalUUID.MatchString(user.VLESSUUID) {
			return fmt.Errorf("%s.vless_uuid must be a canonical lowercase UUID", prefix)
		}
		if len([]byte(user.HY2Password)) < 24 {
			return fmt.Errorf("%s.hy2_password must be at least 24 UTF-8 bytes", prefix)
		}
		if len([]byte(user.SubscriptionToken)) < 24 {
			return fmt.Errorf("%s.subscription_token must be at least 24 UTF-8 bytes", prefix)
		}
		if !user.Protocols.VLESS && !user.Protocols.Hysteria2 {
			return fmt.Errorf("%s.protocols must enable at least one protocol", prefix)
		}

		if err := unique(names, user.Name, prefix+".name"); err != nil {
			return err
		}
		if err := unique(uuids, user.VLESSUUID, prefix+".vless_uuid"); err != nil {
			return err
		}
		if err := unique(passwords, user.HY2Password, prefix+".hy2_password"); err != nil {
			return err
		}
		if err := unique(tokens, user.SubscriptionToken, prefix+".subscription_token"); err != nil {
			return err
		}
		if user.Enabled {
			enabled++
		}
	}

	if enabled == 0 {
		return errors.New("field \"users\" must contain at least one enabled user")
	}
	return nil
}

func validateName(name string) error {
	if !utf8.ValidString(name) {
		return errors.New("must be valid UTF-8")
	}
	count := utf8.RuneCountInString(name)
	if count < 1 || count > 64 {
		return errors.New("must contain 1 to 64 Unicode code points")
	}
	if strings.TrimSpace(name) != name {
		return errors.New("must not have leading or trailing whitespace")
	}
	for _, value := range name {
		if !unicode.IsPrint(value) {
			return errors.New("must contain only printable characters")
		}
	}
	return nil
}

func unique(values map[string]struct{}, value, field string) error {
	if _, exists := values[value]; exists {
		return fmt.Errorf("field %q duplicates another user", field)
	}
	values[value] = struct{}{}
	return nil
}
