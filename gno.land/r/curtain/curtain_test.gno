package curtain

import (
	"strconv"
	"strings"
	"testing"
	"time"
)

var (
	organiser = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
	member    = "g1us8428u2a5satrlxzagqqa5m6vmuze025anjc6gr"
)

func openTestPoll(cur realm, t *testing.T) int {
	t.Helper()
	testing.SetRealm(testing.NewUserRealm(address(organiser)))
	// Fixture proofs are bound to poll id 0, so each test starts from a clean
	// realm and opens its poll first.
	polls = nil
	return CreatePoll(cross(cur), "Ship the demo?", []string{"yes", "no", "later"}, testRoot, 256, time.Now().Unix()+3600)
}

func mustPanic(t *testing.T, want string, fn func()) {
	t.Helper()
	r := revive(fn)
	if r == nil {
		t.Fatalf("expected abort containing %q, got none", want)
	}
	got, ok := r.(string)
	if !ok {
		t.Fatalf("expected abort containing %q, got non-string abort %v", want, r)
	}
	if !strings.Contains(got, want) {
		t.Fatalf("expected abort %q, got %q", want, got)
	}
}

func TestVoteWithRealProofCountsOnce(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)

	p := PollByID(id)
	if p.Tallies[b.Vote] != 1 {
		t.Fatalf("tally for option %d = %d, want 1", b.Vote, p.Tallies[b.Vote])
	}
	if p.Ballots != 1 {
		t.Fatalf("ballots = %d, want 1", p.Ballots)
	}
	if len(p.Nullifiers) != 1 || p.Nullifiers[0] != b.Nullifier {
		t.Fatalf("nullifier not recorded: %v", p.Nullifiers)
	}
}

func TestTwoMembersBothCount(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	for _, b := range testBallots {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	}
	p := PollByID(id)
	if p.Ballots != len(testBallots) {
		t.Fatalf("ballots = %d, want %d", p.Ballots, len(testBallots))
	}
	total := 0
	for _, n := range p.Tallies {
		total += n
	}
	if total != len(testBallots) {
		t.Fatalf("tallies sum to %d, want %d", total, len(testBallots))
	}
}

func TestSameBallotTwiceRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	mustPanic(t, "already cast", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
	if PollByID(id).Ballots != 1 {
		t.Fatal("second ballot changed the tally")
	}
}

func TestProofForOneOptionCannotBeUsedForAnother(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	other := (b.Vote + 1) % 3
	mustPanic(t, "invalid ballot proof", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, other, b.Root, b.Nullifier)
	})
}

func TestProofCannotBeReplayedIntoAnotherPoll(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	// A poll id is a public signal, so moving a ballot to another poll breaks it.
	other := CreatePoll(cross(cur), "other poll", []string{"a", "b", "c"}, testRoot, 256, time.Now().Unix()+3600)
	if other == id {
		t.Fatal("second poll reused the first id")
	}
	mustPanic(t, "invalid ballot proof", func() {
		Vote(cross(cur), other, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
	if PollByID(other).Ballots != 0 {
		t.Fatal("ballot landed in the wrong poll")
	}
}

func TestTamperedProofRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	tampered := b.ProofA[:len(b.ProofA)-2] + "00"
	if tampered == b.ProofA {
		tampered = b.ProofA[:len(b.ProofA)-2] + "01"
	}
	mustPanic(t, "invalid ballot proof", func() {
		Vote(cross(cur), id, tampered, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
}

func TestRootMismatchRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	wrong := strings.Repeat("11", 32)
	mustPanic(t, "different member set", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, wrong, b.Nullifier)
	})
}

func TestOptionOutOfRangeRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	mustPanic(t, "no such option", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, 7, b.Root, b.Nullifier)
	})
}

func TestMalformedProofHexRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	mustPanic(t, "bytes of hex", func() {
		Vote(cross(cur), id, b.ProofA[:10], b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
}

func TestCreatePollValidation(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(address(organiser)))
	deadline := time.Now().Unix() + 60
	mustPanic(t, "empty title", func() {
		CreatePoll(cross(cur), "  ", []string{"a", "b"}, testRoot, 10, deadline)
	})
	mustPanic(t, "2 to 8 options", func() {
		CreatePoll(cross(cur), "one option", []string{"a"}, testRoot, 10, deadline)
	})
	mustPanic(t, "member cap", func() {
		CreatePoll(cross(cur), "cap", []string{"a", "b"}, testRoot, 0, deadline)
	})
	mustPanic(t, "deadline", func() {
		CreatePoll(cross(cur), "deadline", []string{"a", "b"}, testRoot, 10, 0)
	})
}

func TestOnlyOrganiserCanClose(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	testing.SetRealm(testing.NewUserRealm(address(member)))
	mustPanic(t, "only the organiser", func() { Close(cross(cur), id) })

	testing.SetRealm(testing.NewUserRealm(address(organiser)))
	Close(cross(cur), id)
	if !PollByID(id).Closed {
		t.Fatal("close did not take effect")
	}
	mustPanic(t, "already closed", func() { Close(cross(cur), id) })
}

func TestVoteAfterCloseRejected(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	testing.SetRealm(testing.NewUserRealm(address(organiser)))
	Close(cross(cur), id)
	b := testBallots[0]
	mustPanic(t, "poll closed", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
}

func TestVoteAfterDeadlineRejected(cur realm, t *testing.T) {
	polls = nil
	testing.SetRealm(testing.NewUserRealm(address(organiser)))
	id := CreatePoll(cross(cur), "expired", []string{"a", "b", "c"}, testRoot, 10, time.Now().Unix()-1)
	b := testBallots[0]
	mustPanic(t, "deadline passed", func() {
		Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)
	})
}

func TestRenderShowsLiveTally(cur realm, t *testing.T) {
	id := openTestPoll(cur, t)
	b := testBallots[0]
	Vote(cross(cur), id, b.ProofA, b.ProofB, b.ProofC, b.Vote, b.Root, b.Nullifier)

	page := Render(strconv.Itoa(id))
	for _, want := range []string{"Ship the demo?", "Status: **open**", "1/256", "## Tally", "## Membership", "Nullifiers cast: **1**"} {
		if !strings.Contains(page, want) {
			t.Fatalf("rendered poll missing %q\n%s", want, page)
		}
	}
	index := Render("")
	if !strings.Contains(index, "Ship the demo?") {
		t.Fatalf("index does not list the poll:\n%s", index)
	}
	if !strings.Contains(Render("999999"), "No such poll") {
		t.Fatal("unknown path should not render a poll")
	}
}
