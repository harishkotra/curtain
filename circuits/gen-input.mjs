// Builds a deterministic 256-member tree, then writes circuit witness inputs
// for specific members: node gen-input.mjs <index> <vote> [tag]
import { buildPoseidon } from "circomlibjs";
import fs from "node:fs";

const DEPTH = 8;
const poseidon = await buildPoseidon();
const F = poseidon.F;
const h = (arr) => F.toString(poseidon(arr));

const idx = Number(process.argv[2] ?? 5);
const vote = Number(process.argv[3] ?? 1);
const tag = process.argv[4] ?? `${idx}-${vote}`;
const pollId = 0;

const members = [];
for (let i = 0; i < 1 << DEPTH; i++) {
  const secret = 1000000n + BigInt(i) * 7919n;
  members.push({ secret, commitment: h([secret]) });
}

let level = members.map((m) => m.commitment);
const layers = [level];
while (level.length > 1) {
  const next = [];
  for (let i = 0; i < level.length; i += 2) next.push(h([level[i], level[i + 1]]));
  layers.push(next);
  level = next;
}
const root = level[0];

const secret = members[idx].secret;
const pathElements = [];
const pathIndices = [];
let cursor = idx;
for (let d = 0; d < DEPTH; d++) {
  pathElements.push(layers[d][cursor ^ 1]);
  pathIndices.push(cursor & 1);
  cursor >>= 1;
}

const nullifierHash = h([secret, pollId]);

fs.writeFileSync(
  `input-${tag}.json`,
  JSON.stringify(
    {
      secret: secret.toString(),
      pathElements,
      pathIndices: pathIndices.map(String),
      vote: String(vote),
      pollId: String(pollId),
      root,
      nullifierHash,
    },
    null,
    2,
  ),
);

const fixtures = {
  depth: DEPTH,
  root,
  pollId,
  memberCount: members.length,
  commitments: members.slice(0, 8).map((m) => m.commitment),
  secrets: members.slice(0, 8).map((m) => m.secret.toString()),
  ballots: [],
};
const ballotPath = "fixtures.json";
if (fs.existsSync(ballotPath)) {
  const prev = JSON.parse(fs.readFileSync(ballotPath, "utf8"));
  if (prev.ballots) fixtures.ballots = prev.ballots;
}
fixtures.ballots.push({ tag, index: idx, vote, nullifierHash });
fs.writeFileSync(ballotPath, JSON.stringify(fixtures, null, 2));
console.log(`member ${idx} votes ${vote} -> input-${tag}.json, root ${root}, nullifier ${nullifierHash}`);
