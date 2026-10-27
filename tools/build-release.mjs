// Build everything a release ships: every library's .stlib and the signed
// Node UIO board package (.vpp), plus release notes listing what is inside.
// The GitHub release workflow runs this; it runs the same way locally.
//
//   node tools/build-release.mjs --editor <editor executable> --out <dir>
//                                [--user-data <dir>] [--editor-version <tag>]
//
// --editor is the editor executable from an extracted AppImage
// (`<AppImage> --appimage-extract` gives squashfs-root/modbee-openplc-editor).
// Its command line tool builds the libraries.
// --user-data is the editor state directory the build uses. It holds the
// Arduino cores the verify compiles download, so keeping it between runs
// saves fetching them again; without it a temporary one is used.
// The board package is signed with the key at $MODBEE_VPP_KEY (a file path),
// as node-vpp/build-vpp.mjs reads it.
//
// Steps:
// 1. Fetch each library's pinned C/C++ sources (tools/fetch-sources.mjs).
// 2. Build the board package and install it, so each library's verify
//    compile runs against the Node UIO: a library targets the esp32 core,
//    and with no board of that core installed the editor verifies against
//    the AVR simulator instead.
// 3. Build every library found under this repository, the ones a library
//    uses (its project's `data.libraries`) first, installing each as it is built.
// 4. Copy the results to --out as <library>-<version>.stlib and
//    com.modbee.node-<version>.vpp, and write RELEASE-NOTES.md there.

import { execFileSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SKIP = new Set(['.git', 'node_modules', 'build', 'dist', 'internal', 'temp', 'resources'])
const VPP_DIR = join(ROOT, 'modbee-hardware/modbee-hardware-arduino/modbee-node-uio/node-vpp')

function option(name) {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : undefined
}
const editor = option('--editor')
const outArg = option('--out')
const userDataArg = option('--user-data')
const editorVersion = option('--editor-version')
if (!editor || !outArg) {
  console.error(
    'usage: node tools/build-release.mjs --editor <editor executable> --out <dir> [--user-data <dir>] [--editor-version <tag>]',
  )
  process.exit(2)
}
const out = resolve(outArg)

function findLibraries(dir, found = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (!entry.isDirectory() || SKIP.has(entry.name)) continue
    const sub = join(dir, entry.name)
    if (existsSync(join(sub, 'library.json'))) found.push(sub)
    else findLibraries(sub, found)
  }
  return found
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf-8'))
}

// Each library after the ones it uses, so they are installed when it builds.
function buildOrder(libraries) {
  const byName = new Map(libraries.map((lib) => [lib.name, lib]))
  const ordered = []
  const state = new Map()
  const visit = (lib, path) => {
    if (state.get(lib.name) === 'done') return
    if (state.get(lib.name) === 'visiting') throw new Error(`libraries use each other: ${[...path, lib.name].join(' -> ')}`)
    state.set(lib.name, 'visiting')
    for (const used of lib.uses) {
      const dep = byName.get(used)
      if (!dep) throw new Error(`${lib.name} uses ${used}, which is not a library in this repository`)
      visit(dep, [...path, lib.name])
    }
    state.set(lib.name, 'done')
    ordered.push(lib)
  }
  for (const lib of libraries) visit(lib, [])
  return ordered
}

// The editor is an Electron app: ELECTRON_RUN_AS_NODE (set in a VS Code
// terminal) would start it as plain Node, and a CI runner has no display.
const env = { ...process.env }
delete env.ELECTRON_RUN_AS_NODE
delete env.ELECTRON_NO_ATTACH_CONSOLE
const userData = userDataArg ? resolve(userDataArg) : mkdtempSync(join(tmpdir(), 'modbee-release-ud-'))
mkdirSync(userData, { recursive: true })

function cli(...args) {
  const output = execFileSync(
    resolve(editor),
    ['--ozone-platform=headless', '--disable-gpu', '--no-sandbox', '--cli', '--user-data', userData, ...args, '--json'],
    { env, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: 64 * 1024 * 1024 },
  )
  // The result is the last JSON line; anything before it is the editor's own logging.
  const line = output.trim().split('\n').reverse().find((l) => l.startsWith('{'))
  if (!line) throw new Error(`no JSON result from openplc-cli ${args.join(' ')}:\n${output}`)
  const result = JSON.parse(line)
  if (!result.ok) throw new Error(`openplc-cli ${args.join(' ')} failed:\n${JSON.stringify(result, null, 2)}`)
  return result
}

try {
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })

  execFileSync(process.execPath, [join(ROOT, 'tools/fetch-sources.mjs')], { stdio: 'inherit' })

  const manifest = readJson(join(VPP_DIR, 'package/manifest.json'))
  const vppFile = `${manifest.package.id}-${manifest.package.version}.vpp`
  execFileSync(process.execPath, [join(VPP_DIR, 'build-vpp.mjs')], { stdio: 'inherit' })
  copyFileSync(join(VPP_DIR, 'dist', vppFile), join(out, vppFile))
  cli('packages', 'install', join(out, vppFile))
  console.log(`built    ${vppFile} (installed for the verify compiles)`)

  const libraries = findLibraries(ROOT).map((dir) => {
    const { name, version } = readJson(join(dir, 'library.json'))
    const uses = (readJson(join(dir, 'project.json')).data.libraries ?? []).map((l) => l.name)
    const sourcesPath = join(dir, 'sources.json')
    const sources = existsSync(sourcesPath) ? readJson(sourcesPath).resources : {}
    return { dir, name, version, uses, sources, file: `${name}-${version}.stlib` }
  })
  for (const lib of buildOrder(libraries)) {
    const { stlibPath } = cli('library', 'build', lib.dir, '--clean')
    copyFileSync(join(lib.dir, stlibPath), join(out, lib.file))
    cli('library', 'install', join(out, lib.file))
    console.log(`built    ${lib.file}`)
  }

  const rows = libraries.map(({ name, version, file, uses, sources }) => {
    const pins = Object.values(sources).map(
      (s) => `[${s.repo}@${s.ref.length === 40 ? s.ref.slice(0, 7) : s.ref}](https://github.com/${s.repo}/tree/${s.ref})`,
    )
    return `| ${name} | ${version} | \`${file}\` | ${uses.join(', ') || '-'} | ${pins.join(', ') || '-'} |`
  })
  const notes = [
    '## Board package',
    '',
    `\`${vppFile}\`: ${manifest.package.description} Install it in the editor's packages screen (Add from file).`,
    '',
    '## Libraries',
    '',
    "Install a `.stlib` from the editor's Manage libraries screen, together with the libraries it needs. The C/C++ code each one carries comes from the source repositories listed.",
    '',
    '| Library | Version | File | Needs | Sources |',
    '| --- | --- | --- | --- | --- |',
    ...rows,
    '',
    editorVersion ? `Built with the ModBee OpenPLC Editor ${editorVersion}.` : '',
  ]
  writeFileSync(join(out, 'RELEASE-NOTES.md'), notes.join('\n').trimEnd() + '\n')
  console.log(`wrote    ${relative(process.cwd(), join(out, 'RELEASE-NOTES.md'))}`)
} finally {
  if (!userDataArg) rmSync(userData, { recursive: true, force: true })
}
