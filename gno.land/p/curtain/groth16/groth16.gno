// Package groth16 verifies Groth16 proofs over BN254 for realms.
//
// Written against snarkjs/circom artifacts: the verifying key and the public
// signals use snarkjs' ordering and standard big-endian field encoding, and the
// curve arithmetic is delegated to Gno's crypto/bn254 precompiles (the EVM
// alt_bn128 semantics), so a proof produced by snarkjs verifies on chain with no
// trusted verifier oracle and no off-chain helper.
package groth16

import "crypto/bn254"

const (
	g1Len = 64
	g2Len = 128
	fpLen = 32
)

// Verify checks a Groth16 proof: A (G1, 64 bytes), B (G2, 128), C (G1, 64)
// against the key embedded in this package and the public signals in the order
// the circuit declares them.
func Verify(proofA, proofB, proofC []byte, pubSignals [][]byte) bool {
	if len(proofA) != g1Len || len(proofB) != g2Len || len(proofC) != g1Len {
		return false
	}
	if len(pubSignals) != NPublic {
		return false
	}
	for i := 0; i < len(pubSignals); i++ {
		if len(pubSignals[i]) != fpLen {
			return false
		}
	}

	// vk_x = IC[0] + sum(IC[i+1] * s_i)
	vkX := make([]byte, g1Len)
	copy(vkX, vkIC[0])
	for i := 0; i < NPublic; i++ {
		term := g1mul(vkIC[i+1], pubSignals[i])
		if term == nil {
			return false
		}
		next := g1add(vkX, term)
		if next == nil {
			return false
		}
		vkX = next
	}

	// e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1
	negA := negateG1(proofA)
	if negA == nil {
		return false
	}
	input := make([]byte, 0, 4*(g1Len+g2Len))
	input = append(input, negA...)
	input = append(input, proofB...)
	input = append(input, vkAlpha1...)
	input = append(input, vkBeta2...)
	input = append(input, vkX...)
	input = append(input, vkGamma2...)
	input = append(input, proofC...)
	input = append(input, vkDelta2...)

	out := bn254.PairingCheck(input)
	return len(out) == fpLen && out[fpLen-1] == 1
}

func g1add(a, b []byte) []byte {
	if len(a) != g1Len || len(b) != g1Len {
		return nil
	}
	in := make([]byte, 0, 2*g1Len)
	in = append(in, a...)
	in = append(in, b...)
	return bn254.G1Add(in)
}

func g1mul(point, scalar []byte) []byte {
	if len(point) != g1Len || len(scalar) != fpLen {
		return nil
	}
	in := make([]byte, 0, g1Len+fpLen)
	in = append(in, point...)
	in = append(in, scalar...)
	return bn254.G1Mul(in)
}

// negateG1 returns (x, p - y): the group inverse.
func negateG1(point []byte) []byte {
	if len(point) != g1Len {
		return nil
	}
	out := make([]byte, g1Len)
	copy(out[:fpLen], point[:fpLen])
	neg := fpNeg(point[fpLen:])
	copy(out[fpLen:], neg)
	return out
}

// fpNeg returns p - x for a 32-byte big-endian field element.
func fpNeg(x []byte) []byte {
	if isZero(x) {
		return make([]byte, fpLen)
	}
	return fpSub(fieldModulus(), x)
}

// fpSub returns a - b mod p for big-endian 32-byte inputs, assuming a >= b.
func fpSub(a, b []byte) []byte {
	out := make([]byte, fpLen)
	borrow := 0
	for i := fpLen - 1; i >= 0; i-- {
		d := int(a[i]) - int(b[i]) - borrow
		if d < 0 {
			d += 256
			borrow = 1
		} else {
			borrow = 0
		}
		out[i] = byte(d)
	}
	return out
}

func isZero(x []byte) bool {
	for i := 0; i < len(x); i++ {
		if x[i] != 0 {
			return false
		}
	}
	return true
}

// fieldModulus is the BN254 base field modulus p, the field that G1 and G2
// coordinates live in. The scalar field modulus r is a different number and
// using it here silently produces off-curve points.
func fieldModulus() []byte {
	return []byte{
		0x30, 0x64, 0x4e, 0x72, 0xe1, 0x31, 0xa0, 0x29,
		0xb8, 0x50, 0x45, 0xb6, 0x81, 0x81, 0x58, 0x5d,
		0x97, 0x81, 0x6a, 0x91, 0x68, 0x71, 0xca, 0x8d,
		0x3c, 0x20, 0x8c, 0x16, 0xd8, 0x7c, 0xfd, 0x47,
	}
}
