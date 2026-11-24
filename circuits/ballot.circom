pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/bitify.circom";

// Ballot(DEPTH): anonymous eligibility + single-use nullifier + bound vote.
//
// Private: secret, merkle path of the voter's commitment, vote.
// Public:  vote, pollId, root, nullifierHash (in that order).
//
// commitment = Poseidon(secret) sits as a leaf in an organiser-published tree.
// nullifier  = Poseidon(secret, pollId) is published so the realm can reject a
// second ballot from the same secret without ever learning who cast it.
template Ballot(DEPTH) {
    signal input secret;
    signal input pathElements[DEPTH];
    signal input pathIndices[DEPTH];
    signal input vote;
    signal input pollId;
    signal input root;
    signal input nullifierHash;

    // vote is an option index, 0..15
    component voteBits = Num2Bits(4);
    voteBits.in <== vote;

    component commitment = Poseidon(1);
    commitment.inputs[0] <== secret;

    signal level[DEPTH + 1];
    level[0] <== commitment.out;

    signal left[DEPTH];
    signal right[DEPTH];
    component h[DEPTH];

    for (var i = 0; i < DEPTH; i++) {
        // pathIndices must be binary
        pathIndices[i] * (1 - pathIndices[i]) === 0;

        // left  = level[i]        if index = 0 else pathElements[i]
        // right = pathElements[i] if index = 0 else level[i]
        left[i] <== level[i] + pathIndices[i] * (pathElements[i] - level[i]);
        right[i] <== pathElements[i] + pathIndices[i] * (level[i] - pathElements[i]);

        h[i] = Poseidon(2);
        h[i].inputs[0] <== left[i];
        h[i].inputs[1] <== right[i];
        level[i + 1] <== h[i].out;
    }

    level[DEPTH] === root;

    component nullifier = Poseidon(2);
    nullifier.inputs[0] <== secret;
    nullifier.inputs[1] <== pollId;
    nullifier.out === nullifierHash;
}

component main {public [vote, pollId, root, nullifierHash]} = Ballot(8);
