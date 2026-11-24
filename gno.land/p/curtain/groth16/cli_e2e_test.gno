package groth16

import (
	"encoding/hex"
	"testing"
)

func TestCLIProofAccepted(t *testing.T) {
	a, _ := hex.DecodeString("2d2fc7be0c7f76e0718b0efd4dc21c2ad9149c59b178fb9e5a7f16339470ca4a2954c0d78d0c3ff84c1ba3c3c56feae66bae9de510d555f11077bbdcccb5866a")
	b, _ := hex.DecodeString("2afc5bfe93916a16ae89c8cb9a16dfd9f71dc4449dfbc082f4857bd5264c94df2cfaa1bbcc64aced0164469817a79925ef586b175d23c543f142ab4866bc7bc100d1f92947d16cfb90b945750183851693a5c397b50476832792596bbbbae10515f9c86e2b909b1525b2c6533ce4322002e7cb7dd78f2ee5c492c0393c9a27ba")
	c, _ := hex.DecodeString("0be31ca79d2962f26b64250ea8c286b48a16d8a39e1145b03b45d01cb5108bf505eae4198cb708f0f72a7bd7d4eb9dd7d6c5525734b1d7ec3fa2171085b9917a")
	sigs := [][]byte{
		bytes32("0000000000000000000000000000000000000000000000000000000000000001"),
		bytes32("0000000000000000000000000000000000000000000000000000000000000000"),
		bytes32("137197b89dc71065a6b0810e8a43436bc7f1707f4e1716863a8479af701ae003"),
		bytes32("1366972a24b1e6b5b4bf400cdc072259d0e2bd7892e64c0ef2f955ef667eee9a"),
	}
	if !Verify(a, b, c, sigs) {
		t.Fatal("cli proof rejected")
	}
}

func bytes32(hexStr string) []byte {
	b, err := hex.DecodeString(hexStr)
	if err != nil {
		panic(err)
	}
	return b
}
