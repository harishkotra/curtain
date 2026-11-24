# Curtain

Secret ballots for on-chain communities. A member proves they belong to the
voter set and casts a vote, without revealing which member they are. Results are
tallied in public; the ballot is never linked to a name.

Every ballot is a Groth16 proof over BN254, verified inside the realm by a
verifier written in Gno. No oracle, no off-chain tally server, no operator who
can see the votes.

- Realm: `gno.land/r/curtain` (Onyx testnet)
- Verifier: `gno.land/p/curtain/groth16`
- Circuit: `circuits/ballot.circom`

## Why this exists

Polls on-chain today are either public (every vote visible, so no honest
anonymous vote) or off-chain (a spreadsheet, a Discord bot, a server that sees
everything). Gno ships BN254 pairing checks in its standard library, which is
exactly what a Groth16 verifier needs, and nothing used them. Curtain is the
first application to put that primitive to work.

## How a ballot works

```
organiser                          member                       realm
---------                          ------                       -----
commitment_i = Poseidon(secret_i)  secret_i stays local         root stored on poll
root = MerkleRoot(commitments)  -> nullifier = Poseidon(secret_i, pollId)
                                   proof: "I know a secret whose
                                   commitment is under root"
                                                             verify(proof)
                                                             store nullifier
                                                             tally[vote]++
```

- **Membership is private.** The proof shows the secret commits to a leaf under
  the poll's root. The verifier learns nothing else about the leaf position.
- **One vote per member.** The nullifier is deterministic per `(secret, pollId)`,
  so the second ballot from the same member is rejected by the realm. It cannot
  be linked back to the commitment, because the commitment only reveals
  `Poseidon(secret)` and the nullifier reveals `Poseidon(secret, pollId)`.
- **The tally is public and verifiable.** Anyone reading the realm sees the
  option counts, the number of ballots, and the list of nullifiers.
- **No trust in the submitter.** The realm rebuilds the public signals from its
  own stored poll, not from the caller's arguments, so a proof generated for one
  poll, option count or member set cannot be replayed into another.

## Live poll

Open the realm in gnoweb: https://gnoweb.onyx.testnets.gno.land/r/curtain

## Create a poll

```sh
gnokey maketx call \
  -pkgpath gno.land/r/curtain -func CreatePoll \
  -args "Ship the demo on Friday?" \
  -args '["yes","no","later"]' \
  -args <root-hex> -args 256 -args $(($(date +%s)+86400)) \
  -gas-fee 1000000ugnot -gas-wanted 50000000 \
  -broadcast -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land YOUR_KEY
```

`root-hex` is the 32-byte Merkle root over the members' Poseidon commitments.
`memberCap` is the number of members the poll was built for, and it stops the
poll accepting more ballots than there are members. `deadline` is a Unix
timestamp; after it the realm refuses ballots.

## Vote

```sh
node tools/curtain.mjs prove --registry registry.json --member 3 --poll 0 --vote 1
```

That writes the witness, builds the proof, and prints a ready-to-paste
`gnokey` command:

```sh
gnokey maketx call \
  -pkgpath gno.land/r/curtain -func Vote \
  -args 0 \
  -args <proofA> -args <proofB> -args <proofC> \
  -args 1 -args <root> -args <nullifier> \
  -gas-fee 1000000ugnot -gas-wanted 50000000 \
  -broadcast -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land YOUR_KEY
```

The proof generation happens on the member's machine. The secret never leaves
it; only the proof, the root and the nullifier go on-chain.

## Close

```sh
gnokey maketx call -pkgpath gno.land/r/curtain -func Close -args 0 ... 
```

Only the address that created the poll can close it. A closed poll rejects
further ballots and keeps its tally.

## The circuit

`circuits/ballot.circom` (61 lines):

| Signal | Visibility | Meaning |
| --- | --- | --- |
| `vote` | public | chosen option index, 0..15 |
| `pollId` | public | binds the ballot to one poll |
| `root` | public | Merkle root of the member set |
| `nullifierHash` | public | `Poseidon(secret, pollId)` |
| `secret` | private | the member's secret |
| `pathElements[8]` | private | Merkle path |
| `pathIndices[8]` | private | left/right per level |

Constraints: `commitment = Poseidon(secret)` hashes up the provided path to
`root`; `vote` is range-checked with `Num2Bits(4)` and option bounds are enforced
by the realm against the poll's option list.

Depth 8 holds 256 members. Raising it means one constant in the circuit and a
new trusted setup.

## Trusted setup

Groth16 needs a circuit-specific setup. `circuits/` contains the result:

```sh
snarkjs powersoftau new bn128 14 pot14_0.ptau -v
snarkjs powersoftau contribute pot14_0.ptau pot14_1.ptau --name="curtain" -v
snarkjs powersoftau prepare phase2 pot14_1.ptau pot14_final.ptau -v
snarkjs groth16 setup ballot.r1cs pot14_final.ptau ballot_0.zkey
snarkjs zkey contribute ballot_0.zkey ballot_final.zkey --name="curtain" -v
snarkjs zkey export verificationkey ballot_final.zkey vkey.json
```

The proving key (`ballot_final.zkey`) and verification key (`vkey.json`) are
committed. The ptau file is not; regenerate it with the commands above.

Whoever holds the setup contribution could forge proofs, which is why the file
above is a single-party ceremony for a demo and not a production one. For a real
deployment the contribution should be a multi-party ceremony with published
transcript.

## Repository layout

```
circuits/                       circom circuit, proving key, key generator
  ballot.circom                 the circuit
  gen-input.mjs                 builds a member tree and a witness input
  gen-vkey.mjs                  converts snarkjs vkey + proofs into Gno source
tools/curtain.mjs               registry builder and ballot prover
gno.land/p/curtain/groth16/     Groth16 verifier over crypto/bn254
gno.land/r/curtain/             the poll realm and its gnoweb view
```

## Tests

```sh
gno test ./gno.land/p/curtain/groth16/ ./gno.land/r/curtain/
```

The verifier package checks a real snarkjs proof, and rejects it when the vote,
root or nullifier is altered. The realm checks a full ballot end to end: a valid
proof increments the tally once, the same ballot twice aborts on the nullifier,
a proof bound to another poll aborts, and a tampered proof aborts before the
tally moves.

`gno.land/p/curtain/groth16/cli_e2e_test.gno` holds a proof produced by
`tools/curtain.mjs` and asserts the Gno verifier accepts it, so the tool in this
repo and the verifier on-chain cannot drift apart silently.

## Costs

A ballot is one pairing check plus four hash-to-point operations, so voting
costs more gas than a plain transaction but stays inside normal block limits. In
testing a ballot settled around 30M gas; the realm asks for 50M so a vote can be
sent without tuning gas by hand.

## Limits worth knowing

- **The organiser mints the secrets.** A member who is handed a secret can vote
  once, which is the point, but the organiser could also hand out extra secrets.
  The root is public, so the member count is checkable even if the identities
  are not.
- **No delegation, no weighted votes.** One member, one ballot, one option.
- **Deadline is wall-clock block time**, so a poll closes at the first block
  past the timestamp, not exactly on it.
- **Secrets are the ballot.** Lose the secret file and that membership is gone;
  lose it to someone else and they can vote as that member.

## Built by

Built By Harish Kotra — harishkotra.me
Checkout my other builds — dailybuild.xyz
