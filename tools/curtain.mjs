// Curtain CLI: build a member registry and produce ballots you can cast on-chain.
//
//   node tools/curtain.mjs registry --size 8 --out registry.json
//   node tools/curtain.mjs prove --registry registry.json --member 3 --poll 0 --vote 1
//
// The registry holds each member's secret and their Merkle path. Treat it as
// the organiser's private key material: whoever holds a row can vote as that
// member, once, for any poll that uses this root.

import fs from "node:fs";
import { execFileSync } from "node:child_process";
import { buildPoseidon } from "circomlibjs";

const CIRCUITS = new URL("../circuits/", import.meta.url).pathname;

const poseidon = await buildPoseidon();
const F = poseidon.F;
const hash = (arr) => F.toString(poseidon(arr));

const ZERO = hash([0n]);

function padTree(commitments, depth) {
  const size = 1 << depth;
  if (commitments.length > size) {
    throw new Error(`registry has ${commitments.length} members, depth ${depth} holds ${size}`);
  }
  const leaves = commitments.slice();
  while (leaves.length < size) leaves.push(ZERO);

  const layers = [leaves];
  let level = leaves;
  while (level.length > 1) {
    const next = [];
    for (let i = 0; i < level.length; i += 2) next.push(hash([level[i], level[i + 1]]));
    layers.push(next);
    level = next;
  }
  return { layers, root: level[0] };
}

function pathFor(layers, index, depth) {
  const pathElements = [];
  const pathIndices = [];
  let cursor = index;
  for (let d = 0; d < depth; d++) {
    pathElements.push(layers[d][cursor ^ 1]);
    pathIndices.push(cursor & 1);
    cursor >>= 1;
  }
  return { pathElements, pathIndices };
}

function cmdRegistry(args) {
  const size = Number(args.size ?? 8);
  const depth = Number(args.depth ?? 8);
  const out = args.out ?? "registry.json";
  if (size < 1) throw new Error("--size must be at least 1");

  // Deterministic secrets are a demo convenience. For a real poll, generate
  // each secret with a CSPRNG and hand it to that member privately.
  const members = [];
  for (let i = 0; i < size; i++) {
    const secret = 1000000n + BigInt(i) * 7919n;
    members.push({ index: i, secret: secret.toString(), commitment: hash([secret]) });
  }

  const { layers, root } = padTree(members.map((m) => m.commitment), depth);
  for (const m of members) {
    const { pathElements, pathIndices } = pathFor(layers, m.index, depth);
    m.pathElements = pathElements;
    m.pathIndices = pathIndices.map(String);
  }

  const registry = { depth, size, root, members };
  fs.writeFileSync(out, JSON.stringify(registry, null, 2));
  console.log(`wrote ${out}`);
  console.log(`members ${size}, depth ${depth}`);
  console.log(`root    ${root}`);
  console.log("");
  console.log("Publish the root on-chain with CreatePoll, then give each member their");
  console.log("own row of members[] and keep the file itself private.");
}

async function cmdProve(args) {
  const registryPath = args.registry ?? "registry.json";
  const memberIndex = Number(args.member ?? 0);
  const pollId = Number(args.poll ?? 0);
  const vote = Number(args.vote ?? 0);
  const tag = args.tag ?? `m${memberIndex}-p${pollId}-v${vote}`;

  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  const member = registry.members.find((m) => m.index === memberIndex);
  if (!member) throw new Error(`no member ${memberIndex} in ${registryPath}`);

  const nullifierHash = hash([BigInt(member.secret), BigInt(pollId)]);
  const input = {
    secret: member.secret,
    pathElements: member.pathElements,
    pathIndices: member.pathIndices,
    vote: String(vote),
    pollId: String(pollId),
    root: registry.root,
    nullifierHash,
  };

  const inputPath = `${CIRCUITS}input-${tag}.json`;
  const proofPath = `${CIRCUITS}proof-${tag}.json`;
  const publicPath = `${CIRCUITS}public-${tag}.json`;
  const witnessPath = `${CIRCUITS}witness-${tag}.wtns`;
  fs.writeFileSync(inputPath, JSON.stringify(input, null, 2));

  execFileSync("snarkjs", [
    "wtns", "calculate", `${CIRCUITS}ballot_js/ballot.wasm`, inputPath, witnessPath,
  ], { stdio: "inherit" });
  execFileSync("snarkjs", [
    "groth16", "prove", `${CIRCUITS}ballot_final.zkey`, witnessPath, proofPath, publicPath,
  ], { stdio: "inherit" });

  const proof = JSON.parse(fs.readFileSync(proofPath, "utf8"));
  // Field elements are 32-byte big-endian. G2 is emitted imaginary-part first,
  // which is what libff, Solidity's alt_bn128 and our Gno verifier expect.
  const fe = (x) => BigInt(x).toString(16).padStart(64, "0");
  const g1hex = (pt) => pt.slice(0, 2).map(fe).join("");
  const g2hex = (pt) => [pt[0][1], pt[0][0], pt[1][1], pt[1][0]].map(fe).join("");

  console.log("");
  console.log(`ballot for poll ${pollId}, member ${memberIndex}, vote ${vote}`);
  console.log(`proofA ${g1hex(proof.pi_a).slice(0, 24)}...`);
  console.log("");
  console.log("cast it with:");
  console.log(
    [
      "gnokey maketx call \\",
      "  -pkgpath gno.land/r/curtain -func Vote \\",
      `  -args ${pollId} \\`,
      `  -args ${g1hex(proof.pi_a)} \\`,
      `  -args ${g2hex(proof.pi_b)} \\`,
      `  -args ${g1hex(proof.pi_c)} \\`,
      `  -args ${vote} \\`,
      `  -args ${registry.root} \\`,
      `  -args ${nullifierHash} \\`,
      "  -gas-fee 1000000ugnot -gas-wanted 50000000 \\",
      "  -broadcast -chainid onyx-1 -remote https://rpc.onyx.testnets.gno.land YOUR_KEY",
    ].join("\n"),
  );
}

const [command, ...rest] = process.argv.slice(2);
const args = {};
for (let i = 0; i < rest.length; i++) {
  if (rest[i].startsWith("--")) {
    args[rest[i].slice(2)] = rest[i + 1]?.startsWith("--") ? "true" : rest[i + 1];
    if (rest[i + 1] && !rest[i + 1].startsWith("--")) i++;
  }
}

if (command === "registry") cmdRegistry(args);
else if (command === "prove") await cmdProve(args);
else {
  console.log("usage: node tools/curtain.mjs <registry|prove> [flags]");
  process.exit(1);
}
