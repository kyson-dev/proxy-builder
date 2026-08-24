package contracts

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
)

func RenderSingBox(templateData []byte, users UsersDocument, release Release, privateKey, obfsPassword string) ([]byte, error) {
	if err := users.Validate(); err != nil {
		return nil, err
	}
	if err := release.Validate(); err != nil {
		return nil, err
	}
	if len([]byte(obfsPassword)) < 24 {
		return nil, errors.New("obfs password must be at least 24 UTF-8 bytes")
	}
	derived, err := DeriveReality(privateKey)
	if err != nil {
		return nil, err
	}
	realityHost, realityPort, err := SplitHostPort(release.RealityDest)
	if err != nil {
		return nil, fmt.Errorf("release reality_dest: %w", err)
	}

	decoder := json.NewDecoder(bytes.NewReader(templateData))
	decoder.UseNumber()
	var root map[string]any
	if err := decoder.Decode(&root); err != nil {
		return nil, errors.New("sing-box template JSON is invalid")
	}
	var trailing any
	if err := decoder.Decode(&trailing); err == nil {
		return nil, errors.New("sing-box template contains a trailing JSON value")
	} else if !errors.Is(err, io.EOF) {
		return nil, errors.New("sing-box template JSON is invalid")
	}
	inbounds, ok := root["inbounds"].([]any)
	if !ok {
		return nil, errors.New("sing-box template field \"inbounds\" must be an array")
	}

	vlessCount := 0
	hy2Count := 0
	for _, rawInbound := range inbounds {
		inbound, ok := rawInbound.(map[string]any)
		if !ok {
			return nil, errors.New("sing-box template contains a non-object inbound")
		}
		switch inbound["type"] {
		case "vless":
			vlessCount++
			vlessUsers := make([]any, 0, len(users.Users))
			for _, user := range users.Users {
				if user.Enabled && user.Protocols.VLESS {
					vlessUsers = append(vlessUsers, map[string]any{
						"name": user.Name,
						"uuid": user.VLESSUUID,
						"flow": "xtls-rprx-vision",
					})
				}
			}
			inbound["users"] = vlessUsers
			tls, err := requiredObject(inbound, "tls")
			if err != nil {
				return nil, err
			}
			tls["server_name"] = realityHost
			reality, err := requiredObject(tls, "reality")
			if err != nil {
				return nil, err
			}
			handshake, err := requiredObject(reality, "handshake")
			if err != nil {
				return nil, err
			}
			handshake["server"] = realityHost
			handshake["server_port"] = realityPort
			reality["private_key"] = privateKey
			reality["short_id"] = []any{derived.ShortID}
		case "hysteria2":
			hy2Count++
			hy2Users := make([]any, 0, len(users.Users))
			for _, user := range users.Users {
				if user.Enabled && user.Protocols.Hysteria2 {
					hy2Users = append(hy2Users, map[string]any{
						"name":     user.Name,
						"password": user.HY2Password,
					})
				}
			}
			inbound["users"] = hy2Users
			inbound["masquerade"] = "https://" + release.HY2SNI
			obfs, err := requiredObject(inbound, "obfs")
			if err != nil {
				return nil, err
			}
			obfs["type"] = "salamander"
			obfs["password"] = obfsPassword
		}
	}
	if vlessCount != 1 || hy2Count != 1 {
		return nil, errors.New("sing-box template must contain exactly one VLESS and one Hysteria2 inbound")
	}

	output, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, errors.New("generated sing-box config cannot be encoded")
	}
	return append(output, '\n'), nil
}

func requiredObject(parent map[string]any, field string) (map[string]any, error) {
	value, ok := parent[field].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("sing-box template field %q must be an object", field)
	}
	return value, nil
}
