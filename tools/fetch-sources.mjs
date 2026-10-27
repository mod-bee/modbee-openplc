// Fetch each library's C/C++ sources into its resources/ folder from GitHub,
// at the repository and ref its sources.json pins.
//
//   node tools/fetch-sources.mjs              every library in this repository
//   node tools/fetch-sources.mjs <lib> ...    only those library folders
//   node tools/fetch-sources.mjs --check      say which folders differ from their pin; change nothing
//
// sources.json sits beside a library's library.json:
//
//   { "resources": { "<folder>": { "repo": "owner/name", "ref": "<tag or full commit id>",
//                                   "path": "<folder in the repository, \"\" for its root>",
//                                   "include": ["library.properties", "src", "LICENSE"] } } }
//
// Each resources/<folder> is replaced as a whole by the listed files of the
// repository at that ref. The fetched folders are gitignored: the pin is the
// one source of truth, so there is no copy to drift. Folders a library keeps
// in this repository (not listed in sources.json) are left alone.
//
// To fetch from local clones instead (e.g. before a tag is pushed), use git's
// own URL rewrite, which this script inherits:
//   GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url./path/to/clones/.insteadOf \
//   GIT_CONFIG_VALUE_0=https://github.com/mod-bee/ node tools/fetch-sources.mjs

import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SKIP = new Set(['.git', 'node_modules', 'build', 'dist', 'internal', 'temp', 'resources'])

const args = process.argv.slice(2)
const check = args.includes('--check')
const named = args.filter((a) => a !== '--check').map((a) => resolve(a))

function findLibraries(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || SKIP.has(entry.name)) continue
    const sub = join(dir, entry.name)
    if (existsSync(join(sub, 'sources.json'))) out.push(sub)
    findLibraries(sub, out)
  }
  return out
}

function listFiles(dir, base = dir, out = new Map()) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) listFiles(path, base, out)
    else out.set(relative(base, path), readFileSync(path))
  }
  return out
}

function sameTree(a, b) {
  if (!existsSync(a) || !existsSync(b)) return false
  const fa = listFiles(a)
  const fb = listFiles(b)
  if (fa.size !== fb.size) return false
  for (const [rel, data] of fa) if (!fb.get(rel)?.equals(data)) return false
  return true
}

const work = mkdtempSync(join(tmpdir(), 'modbee-sources-'))
const checkouts = new Map()

// One shallow fetch per repository and ref. `git fetch <url> <ref>` takes a
// tag name or a full commit id alike.
function checkout(repo, ref) {
  const key = `${repo}@${ref}`
  if (checkouts.has(key)) return checkouts.get(key)
  const dir = mkdtempSync(join(work, 'src-'))
  const git = (...a) => execFileSync('git', ['-C', dir, ...a], { stdio: ['ignore', 'ignore', 'inherit'] })
  git('init', '-q')
  git('fetch', '-q', '--depth', '1', `https://github.com/${repo}`, ref)
  git('checkout', '-q', 'FETCH_HEAD')
  checkouts.set(key, dir)
  return dir
}

function stage(spec, dest) {
  const src = join(checkout(spec.repo, spec.ref), spec.path ?? '')
  for (const item of spec.include) {
    const from = join(src, item)
    if (!existsSync(from)) throw new Error(`${spec.repo}@${spec.ref} has no ${join(spec.path ?? '', item)}`)
    cpSync(from, join(dest, item), { recursive: true })
  }
}

let drifted = 0
try {
  const libraries = named.length > 0 ? named : findLibraries(ROOT)
  for (const lib of libraries) {
    const { resources } = JSON.parse(readFileSync(join(lib, 'sources.json'), 'utf-8'))
    for (const [folder, spec] of Object.entries(resources)) {
      const dest = join(lib, 'resources', folder)
      const pin = `${spec.repo}@${spec.ref}`
      const shown = relative(ROOT, dest)
      if (check) {
        const staged = mkdtempSync(join(work, 'stage-'))
        stage(spec, staged)
        if (sameTree(staged, dest)) console.log(`matches  ${shown}  ${pin}`)
        else {
          console.log(`DIFFERS  ${shown}  ${pin}`)
          drifted++
        }
      } else {
        rmSync(dest, { recursive: true, force: true })
        stage(spec, dest)
        console.log(`fetched  ${shown}  ${pin}`)
      }
    }
  }
} finally {
  rmSync(work, { recursive: true, force: true })
}
if (drifted > 0) {
  console.error(`${drifted} folder(s) differ from their pin; run without --check to fetch them`)
  process.exit(1)
}
