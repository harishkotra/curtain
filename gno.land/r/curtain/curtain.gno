// Curtain: the secret ballot for on-chain communities.
//
// An organiser commits a Merkle root of member commitments. A member proves, in
// zero knowledge, that their commitment is under that root, and casts a ballot
// with a nullifier unique per poll. On chain there is a tally increment and a
// nullifier hash. There is no address, no name, and no way to link the ballot
// back to the voter. Uniqueness is enforced by the nullifier, so nobody can vote
// twice, and anyone can recompute the root from the published commitments.
package curtain

import (
	"strconv"
	"strings"
	"time"

	"chain/runtime/unsafe"

	"gno.land/p/curtain/groth16"
)

const (
	maxOptions  = 8
	maxTitleLen = 80
	version     = "0.1.0"
)

type Poll struct {
	ID         int
	Title      string
	Options    []string
	Root       []byte
	MemberCap  int
	Deadline   int64
	Tallies    []int
	Ballots    int
	Closed     bool
	Creator    address
	Nullifiers []string
}

var polls []*Poll

// CreatePoll opens a poll for the members committed under rootHex.
// Any address can open a poll: the member list is the organiser's claim, and its
// commitments are public, so the root can be recomputed and checked by anyone.
func CreatePoll(cur realm, title string, options []string, rootHex string, memberCap int, deadline int64) int {
	if len(strings.TrimSpace(title)) == 0 {
		panic("curtain: empty title")
	}
	if len(title) > maxTitleLen {
		panic("curtain: title too long")
	}
	if len(options) < 2 || len(options) > maxOptions {
		panic("curtain: need 2 to 8 options")
	}
	root := hexDecode(rootHex, 32)
	if memberCap < 1 || memberCap > 256 {
		panic("curtain: member cap must be 1..256")
	}
	if deadline <= 0 {
		panic("curtain: deadline required")
	}

	p := &Poll{
		ID:        len(polls),
		Title:     title,
		Options:   options,
		Root:      root,
		MemberCap: memberCap,
		Deadline:  deadline,
		Tallies:   make([]int, len(options)),
		Creator:   unsafe.PreviousRealm().Address(),
	}
	polls = append(polls, p)
	return p.ID
}

// Vote verifies a Groth16 ballot and records its nullifier.
//
// proof is the three-point proof (A, B, C) as hex. The public signals are
// rebuilt from the arguments and the stored poll, never taken from the caller,
// so a valid proof cannot be replayed into a different poll, option count or
// member set.
func Vote(cur realm, pollID int, proofAHex, proofBHex, proofCHex string, voteOption int, rootHex, nullifierHex string) {
	p := poll(pollID)
	if p.Closed {
		panic("curtain: poll closed")
	}
	if voteOption < 0 || voteOption >= len(p.Options) {
		panic("curtain: no such option")
	}
	if p.Deadline > 0 && time.Now().Unix() > p.Deadline {
		panic("curtain: deadline passed")
	}
	if p.Ballots >= p.MemberCap {
		panic("curtain: every member has already voted")
	}

	proofA := hexDecode(proofAHex, 64)
	proofB := hexDecode(proofBHex, 128)
	proofC := hexDecode(proofCHex, 64)
	rootGiven := hexDecode(rootHex, 32)
	if !bytesEqual(rootGiven, p.Root) {
		panic("curtain: proof is for a different member set")
	}
	nullifier := hexDecode(nullifierHex, 32)
	if p.hasNullifier(nullifierHex) {
		panic("curtain: this ballot was already cast")
	}

	// Public signal order comes from the circuit: [vote, pollId, root, nullifierHash]
	signals := [][]byte{
		uint32Bytes(voteOption),
		uint32Bytes(pollID),
		rootGiven,
		nullifier,
	}
	if !groth16.Verify(proofA, proofB, proofC, signals) {
		panic("curtain: invalid ballot proof")
	}

	p.Tallies[voteOption]++
	p.Ballots++
	p.Nullifiers = append(p.Nullifiers, nullifierHex)
}

// Close freezes a poll. Only the creator can close, and only once.
func Close(cur realm, pollID int) {
	p := poll(pollID)
	if p.Closed {
		panic("curtain: already closed")
	}
	if unsafe.PreviousRealm().Address() != p.Creator {
		panic("curtain: only the organiser can close this poll")
	}
	p.Closed = true
}

func poll(id int) *Poll {
	if id < 0 || id >= len(polls) {
		panic("curtain: no such poll")
	}
	return polls[id]
}

// PollCount returns how many polls have been opened.
func PollCount() int { return len(polls) }

// PollByID returns a poll by id.
func PollByID(id int) *Poll { return poll(id) }

func (p *Poll) hasNullifier(n string) bool {
	for i := 0; i < len(p.Nullifiers); i++ {
		if p.Nullifiers[i] == n {
			return true
		}
	}
	return false
}

func (p *Poll) Turnout() int { return p.Ballots }

func (p *Poll) TurnoutPct() int {
	if p.MemberCap == 0 {
		return 0
	}
	return p.Ballots * 100 / p.MemberCap
}

// WinningOption returns the leading option index and whether it is tied.
func (p *Poll) WinningOption() (int, bool) {
	best := 0
	tie := false
	for i := 1; i < len(p.Tallies); i++ {
		if p.Tallies[i] > p.Tallies[best] {
			best = i
			tie = false
		} else if p.Tallies[i] == p.Tallies[best] {
			tie = true
		}
	}
	return best, tie
}

func (p *Poll) Status() string {
	if p.Closed {
		return "closed"
	}
	return "open"
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// uint32Bytes encodes a small integer as a 32-byte big-endian field element,
// matching how snarkjs serialises public signals.
func uint32Bytes(v int) []byte {
	out := make([]byte, 32)
	out[28] = byte((v >> 24) & 0xff)
	out[29] = byte((v >> 16) & 0xff)
	out[30] = byte((v >> 8) & 0xff)
	out[31] = byte(v & 0xff)
	return out
}

func hexDecode(s string, want int) []byte {
	if len(s) != want*2 {
		panic("curtain: expected " + strconv.Itoa(want) + " bytes of hex")
	}
	b := []byte(s)
	out := make([]byte, want)
	for i := 0; i < want; i++ {
		out[i] = hexVal(b[i*2])<<4 | hexVal(b[i*2+1])
	}
	return out
}

func hexVal(c byte) byte {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10
	}
	panic("curtain: bad hex character")
}

// HexEncode renders bytes as lowercase hex, for proofs and roots.
func HexEncode(b []byte) string {
	const digits = "0123456789abcdef"
	out := make([]byte, len(b)*2)
	for i := 0; i < len(b); i++ {
		out[i*2] = digits[b[i]>>4]
		out[i*2+1] = digits[b[i]&0x0f]
	}
	return string(out)
}
