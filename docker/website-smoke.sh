#!/bin/bash
# Offline Ruby/Bundler -> HTML -> Python HTTP -> Chromium check. No Apple SDKs.
# Jekyll and plugins belong to each website's Gemfile; this checks image tooling.
set -euo pipefail
work=$(mktemp -d)
server=
trap 'if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true; wait "$server" 2>/dev/null || true; fi; rm -rf "$work"' EXIT
printf 'source "https://rubygems.org"\n' > "$work/Gemfile"
(cd "$work" && bundle check)
ruby -rerb -e 'puts ERB.new("<!doctype html><title><%= 6 * 7 %></title><h1>Website smoke</h1>").result' > "$work/index.html"
python3 - "$work" <<'PY' &
import http.server, pathlib, sys
root=pathlib.Path(sys.argv[1])
class Handler(http.server.SimpleHTTPRequestHandler):
 def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(root),**kwargs)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
(root/'port').write_text(str(server.server_port))
server.serve_forever()
PY
server=$!
for _attempt in {1..100}; do
  [[ -s "$work/port" ]] && break
  kill -0 "$server"
  sleep 0.1
done
NODE_PATH="$(npm root -g)" node - "$work/port" <<'JS'
const fs = require('node:fs');
const { chromium } = require('@playwright/test');
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    const address = `http://127.0.0.1:${fs.readFileSync(process.argv[2], 'utf8')}/`;
    await page.route('**/*', route => route.request().url().startsWith(address)
      ? route.continue() : route.abort());
    await page.goto(address);
    if (await page.title() !== '42' || await page.locator('h1').innerText() !== 'Website smoke')
      throw Error('Generated website did not render');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
JS
printf '%s\n' 'PASS: offline Ruby/Bundler, Python serving and Chromium rendering'
