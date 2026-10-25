#!/usr/bin/env node
// Sign package/ and pack it into dist/<id>-<version>.vpp, the format the
// OpenPLC Editor's "Add from file…" (and `openplc-cli packages install`) takes.
//
//   node build-vpp.mjs [private-key.pem]
//
// The key defaults to $MODBEE_VPP_KEY, then ~/.config/modbee/vpp-signing/modbee-2026.pem.
// The editor must trust its public key (modbee-2026.pub.pem) under the key id
// below, in src/backend/shared/utils/vpp/trusted-keys.ts.
//
// signature.json follows the editor's verifier
// (src/backend/shared/utils/vpp/package-verification-core.ts): the SHA-256 of
// every file, plus the package id and version, Ed25519-signed over the
// canonical JSON (keys sorted, no whitespace).

import { createHash, createPrivateKey, sign } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, sep } from 'node:path'
import { fileURLToPath } from 'node:url'

const KEY_ID = 'modbee-2026'
const here = dirname(fileURLToPath(import.meta.url))
const src = join(here, 'package')
const keyPath =
  process.argv[2] ?? process.env.MODBEE_VPP_KEY ?? join(homedir(), '.config/modbee/vpp-signing/modbee-2026.pem')

function canonicalize(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)
  if (Array.isArray(value)) return `[${value.map(canonicalize).join(',')}]`
  return `{${Object.keys(value)
    .sort()
    .map((k) => `${JSON.stringify(k)}:${canonicalize(value[k])}`)
    .join(',')}}`
}

function listFiles(dir) {
  const out = []
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) out.push(...listFiles(full))
    else out.push(full)
  }
  return out
}

const manifest = JSON.parse(readFileSync(join(src, 'manifest.json'), 'utf-8'))
const { id, version } = manifest.package

const files = {}
for (const full of listFiles(src).sort()) {
  const rel = relative(src, full).split(sep).join('/')
  if (rel === 'signature.json') continue
  files[rel] = createHash('sha256').update(readFileSync(full)).digest('hex')
}

const payload = {
  formatVersion: '1.0',
  alg: 'ed25519',
  keyId: KEY_ID,
  packageId: id,
  version,
  signedAt: new Date().toISOString(),
  files,
}
const key = createPrivateKey(readFileSync(keyPath))
const signature = sign(null, Buffer.from(canonicalize(payload), 'utf-8'), key).toString('base64')

const stage = mkdtempSync(join(tmpdir(), 'vpp-'))
try {
  cpSync(src, stage, { recursive: true })
  writeFileSync(join(stage, 'signature.json'), JSON.stringify({ ...payload, signature }, null, 2) + '\n')
  const dist = join(here, 'dist')
  mkdirSync(dist, { recursive: true })
  const out = join(dist, `${id}-${version}.vpp`)
  rmSync(out, { force: true })
  execFileSync('zip', ['-q', '-r', '-X', out, '.'], { cwd: stage })
  console.log(`${out}\n  ${Object.keys(files).length} files signed with ${KEY_ID}`)
} finally {
  rmSync(stage, { recursive: true, force: true })
}
