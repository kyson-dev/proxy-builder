package contracts

import "testing"

func TestDeriveRealityRFC7748Vector(t *testing.T) {
	derived, err := DeriveReality("dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo")
	if err != nil {
		t.Fatalf("DeriveReality() error = %v", err)
	}
	if derived.PublicKey != "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo" {
		t.Fatalf("public key = %q", derived.PublicKey)
	}
	if derived.ShortID != "c9ccbbf12f7c2cf4" {
		t.Fatalf("short ID = %q", derived.ShortID)
	}
}

func TestDeriveRealityRejectsPaddingAndLength(t *testing.T) {
	for _, input := range []string{"", "dGVzdA==", "dGVzdA"} {
		if _, err := DeriveReality(input); err == nil {
			t.Fatalf("DeriveReality(%q) unexpectedly succeeded", input)
		}
	}
}
