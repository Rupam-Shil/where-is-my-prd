// Opens a Take One project in the editor with ?autoExport=file, the same route the app
// takes for "Record & save", and waits until the export lands on disk.
// Settings (format, GIF height, export folder) come from Take One's settings.json.
//
// Usage: node take-one-export.mjs "<Take One.app>" "<project.takeone>" "<expected output file>"

import { spawn, execFileSync } from 'node:child_process'
import { existsSync, statSync } from 'node:fs'

const [appPath, project, output] = process.argv.slice(2)
if (!appPath || !project || !output) {
  console.error('usage: node take-one-export.mjs <Take One.app> <project.takeone> <output file>')
  process.exit(2)
}

const port = 9339
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const app = spawn(`${appPath}/Contents/MacOS/Take One`, [`--remote-debugging-port=${port}`], { stdio: 'ignore' })

async function mainWindow() {
  for (let i = 0; i < 120; i++) {
    try {
      const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
      const main = targets.find((t) => t.type === 'page' && /#\/(home|welcome)/.test(t.url))
      if (main) return main
    } catch {
      // not listening yet
    }
    await sleep(500)
  }
  throw new Error('Take One main window never appeared')
}

function exporting() {
  try {
    execFileSync('pgrep', ['-f', `ffmpeg.*${output.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`])
    return true
  } catch {
    return false
  }
}

try {
  const target = await mainWindow()
  const ws = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((resolve, reject) => {
    ws.onopen = resolve
    ws.onerror = reject
  })
  await sleep(1500)
  const hash = `/editor?project=${encodeURIComponent(project)}&autoExport=file`
  ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: `location.hash = ${JSON.stringify(hash)}` } }))
  console.log('editor opened, exporting…')

  // Done once the file exists, ffmpeg has exited, and the size has been stable for 5s.
  let lastSize = -1
  let stableFor = 0
  for (let waited = 0; waited < 20 * 60 * 1000; waited += 1000) {
    await sleep(1000)
    if (!existsSync(output)) continue
    const size = statSync(output).size
    stableFor = size === lastSize && size > 0 && !exporting() ? stableFor + 1 : 0
    lastSize = size
    if (stableFor >= 5) {
      console.log(`exported ${output} (${(size / 1024 / 1024).toFixed(1)} MB)`)
      ws.close()
      break
    }
  }
  if (stableFor < 5) throw new Error('export did not finish within 20 minutes')
} finally {
  app.kill()
}
