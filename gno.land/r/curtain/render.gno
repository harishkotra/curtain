package curtain

import (
	"strconv"
	"strings"
)

const barWidth = 24

// Render is the gnoweb view: a poll index at /r/curtain and a poll page at
// /r/curtain:<id>. Nothing here trusts the caller; it only formats state.
func Render(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return renderIndex()
	}
	id, err := strconv.Atoi(path)
	if err != nil || id < 0 || id >= len(polls) {
		return "# Curtain\n\nNo such poll.\n"
	}
	return renderPoll(polls[id])
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString("# Curtain\n\n")
	b.WriteString("A secret ballot for on-chain communities. Votes carry a zero-knowledge proof of membership, so the tally is public while the voter is not.\n\n")
	b.WriteString("Every ballot is a Groth16 proof over BN254: it shows your commitment is under the published member root and publishes only a nullifier, which stops one member voting twice without revealing which member voted how.\n\n")

	if len(polls) == 0 {
		b.WriteString("No polls yet. The first one is one command away.\n")
		return b.String()
	}

	b.WriteString("## Polls\n\n")
	for _, p := range polls {
		best, tie := p.WinningOption()
		lead := p.Options[best]
		if tie {
			lead = "tied"
		}
		b.WriteString("* [" + p.Title + "](" + strconv.Itoa(p.ID) + ") - " + p.Status() +
			", " + strconv.Itoa(p.Ballots) + "/" + strconv.Itoa(p.MemberCap) + " ballots" +
			", leading: " + lead + "\n")
	}
	b.WriteString("\n")
	return b.String()
}

func renderPoll(p *Poll) string {
	var b strings.Builder
	b.WriteString("# " + p.Title + "\n\n")
	b.WriteString("Status: **" + p.Status() + "**. Ballots: **" + strconv.Itoa(p.Ballots) +
		"/" + strconv.Itoa(p.MemberCap) + "** (" + strconv.Itoa(p.TurnoutPct()) + "%).\n\n")

	b.WriteString("## Tally\n\n")
	total := p.Ballots
	if total == 0 {
		total = 1
	}
	for i, opt := range p.Options {
		filled := p.Tallies[i] * barWidth / total
		bar := strings.Repeat("#", filled) + strings.Repeat(".", barWidth-filled)
		pct := p.Tallies[i] * 100 / total
		b.WriteString(strconv.Itoa(i) + ". " + opt + "\n\n")
		b.WriteString("   `" + bar + "` " + strconv.Itoa(p.Tallies[i]) + " (" + strconv.Itoa(pct) + "%)\n\n")
	}

	best, tie := p.WinningOption()
	if p.Ballots > 0 {
		if tie {
			b.WriteString("No leader yet: the top options are tied.\n\n")
		} else {
			b.WriteString("Leading: **" + p.Options[best] + "**\n\n")
		}
	}

	b.WriteString("## Membership\n\n")
	b.WriteString("Member root: `" + HexEncode(p.Root) + "`\n\n")
	b.WriteString("Each member holds a secret whose Poseidon commitment is a leaf under this root. Recompute the root from the published commitments to check the member set yourself.\n\n")

	if p.Closed {
		b.WriteString("This poll is closed. The tally and the nullifier list are final.\n\n")
	} else {
		b.WriteString("## Casting a ballot\n\n")
		b.WriteString("Proving happens off chain, because a browser or a laptop can run the prover but the chain only needs to check it.\n\n")
		b.WriteString("```\n")
		b.WriteString("curtain prove --poll " + strconv.Itoa(p.ID) + " --vote <option> --secret <your secret>\n")
		b.WriteString("```\n\n")
		b.WriteString("The prover prints `proofA`, `proofB`, `proofC`, the `root` and a `nullifier`, then the vote call:\n\n")
		b.WriteString("```\n")
		b.WriteString("gnokey maketx call -pkgpath gno.land/r/curtain -func Vote -args " + strconv.Itoa(p.ID) +
			" -args <proofA> -args <proofB> -args <proofC> -args <option> -args <root> -args <nullifier> -gasfee 1000000 -broadcast -chainid <chain> <key>\n")
		b.WriteString("```\n\n")
		b.WriteString("The nullifier is `Poseidon(secret, pollId)`: the same secret voted twice in this poll gives the same nullifier, so a second ballot is rejected. Nothing else about the voter is published.\n\n")
	}

	b.WriteString("## Verification\n\n")
	b.WriteString("Nullifiers cast: **" + strconv.Itoa(len(p.Nullifiers)) + "**\n\n")
	if len(p.Nullifiers) > 0 {
		b.WriteString("```\n")
		for _, n := range p.Nullifiers {
			b.WriteString(n + "\n")
		}
		b.WriteString("```\n\n")
	}
	b.WriteString("These are hashes. They are unique per ballot, and they cannot be turned back into a member.\n")
	return b.String()
}
