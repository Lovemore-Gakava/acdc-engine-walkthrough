// Capture the nine inputs CDISC's app hands its R engine, for one saved chain.
//
// Runs the real app (ac-dc-app, from cdisc-org/analysis-concepts) in headless
// Chrome. Two of its files are replaced as they are served, and nothing on disk
// is changed:
//   js/utils/webr-engine.js        -> webr-recorder.js: records instead of running R
//   js/views/execute-analysis.js   -> the original, plus one line exposing two functions
// The study, the chain and the dataset metadata are served from the paths below,
// so neither checkout needs staging.
//
// Usage (see capture/README.md):
//   node capture/capture.mjs --app <analysis-concepts checkout> --factory <usdm-acdc-in-practice checkout>
//                            --meta <dataset-meta.json> --out inputs [--chrome /path/to/chrome]

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const here = path.dirname(fileURLToPath(import.meta.url));
const arg = (name, dflt) => {
  const i = process.argv.indexOf(`--${name}`);
  if (i > 0) return process.argv[i + 1];
  if (dflt !== undefined) return dflt;
  throw new Error(`missing --${name}`);
};
const APP = path.resolve(arg('app'));
const FACTORY = path.resolve(arg('factory'));
const META = JSON.parse(fs.readFileSync(arg('meta'), 'utf8'));
const OUT = path.resolve(arg('out'));
const CHROME = arg('chrome', '');
const SETTINGS = JSON.parse(fs.readFileSync(path.join(here, 'step8-settings.json'), 'utf8'));
const USDM = path.join(FACTORY, 'study', 'usdm', 'toriva-lung-301.usdm.json');
const CHAIN = path.join(FACTORY, 'endpoints', '01-simple-lab-cfb', 'chain.json');

// A plain static server over the app checkout.
const types = { '.js': 'text/javascript', '.json': 'application/json', '.html': 'text/html', '.css': 'text/css' };
const server = http.createServer((req, res) => {
  const p = path.join(APP, decodeURIComponent(new URL(req.url, 'http://x').pathname));
  if (!p.startsWith(APP) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, r));
const base = `http://localhost:${server.address().port}`;

const browser = await chromium.launch(CHROME ? { executablePath: CHROME } : {});
const page = await browser.newPage();
page.on('pageerror', e => console.error('[page error]', e.message));

const serve = (body, type = 'application/json') => r => r.fulfill({ contentType: type, body });
await page.route('**/js/utils/webr-engine.js*',
  serve(fs.readFileSync(path.join(here, 'webr-recorder.js'), 'utf8'), 'text/javascript'));
await page.route('**/js/views/execute-analysis.js*', serve(
  fs.readFileSync(path.join(APP, 'ac-dc-app', 'js', 'views', 'execute-analysis.js'), 'utf8') +
  '\nwindow.__acdc = { _executeAnalysis, _ensureEndpointResult };\n', 'text/javascript'));
await page.route('**/data/usdm/studies.json', async r => {
  const s = JSON.parse(fs.readFileSync(path.join(APP, 'ac-dc-app', 'data', 'usdm', 'studies.json'), 'utf8'));
  (Array.isArray(s) ? s : s.studies).push({ file: 'toriva-lung-301.usdm.json' });
  return r.fulfill({ contentType: 'application/json', body: JSON.stringify(s) });
});
await page.route('**/data/usdm/toriva-lung-301.usdm.json', serve(fs.readFileSync(USDM, 'utf8')));
await page.route('**/__capture/chain.json', serve(fs.readFileSync(CHAIN, 'utf8')));
await page.addInitScript(m => { window.__meta = m; }, META);

await page.goto(`${base}/ac-dc-app/index.html`);
await page.waitForFunction(() => window.appState?.loaded, null, { timeout: 60000 });

const out = await page.evaluate(async (s) => {
  const ser = await import('/ac-dc-app/js/utils/instance-serializer.js');
  const app = await import('/ac-dc-app/js/app.js');
  const w = await import('/ac-dc-app/js/utils/webr-engine.js');
  ser.deserializeStudyInstance(await (await fetch('/__capture/chain.json')).json(), window.appState);
  app.rebuildSpec();
  await import('/ac-dc-app/js/views/execute-analysis.js');
  for (const name of Object.keys(window.__meta)) await w.loadXptFile(null, name);
  window.appState.loadedDatasets = w.getLoadedDatasets();
  const rs = window.__acdc._ensureEndpointResult(s.endpoint);
  rs.datasetOverride = s.datasetOverride;
  rs.varOverrides = s.varOverrides;
  rs.sliceOverrides = s.sliceOverrides;
  await window.__acdc._executeAnalysis(document.createElement('div'), s.endpoint, 0);
  return { json: window.__cap.json, code: window.__cap.code,
           result: window.appState.endpointResults[s.endpoint]?.analysisResults?.[0] };
}, SETTINGS);

if (out.result?.status !== 'complete') throw new Error(`the app did not reach the engine: ${out.result?.error}`);
const names = { spec_json: 'spec', mapping_json: 'mapping', method_json: 'method', r_impl_json: 'r_impl',
  overrides_json: 'overrides', derivations_json: 'derivations', unit_conversions_json: 'unit_conversions',
  r_impls_json: 'r_impls', concept_categories_json: 'concept_categories' };
fs.mkdirSync(OUT, { recursive: true });
for (const [k, v] of Object.entries(out.json)) {
  fs.writeFileSync(path.join(OUT, `${names[k] || k}.json`), JSON.stringify(JSON.parse(v), null, 2) + '\n');
}
fs.writeFileSync(path.join(OUT, 'bootstrap.R'), out.code.join('\n\n') + '\n');
console.log(`wrote ${Object.keys(out.json).length} inputs and bootstrap.R to ${OUT}`);
await browser.close();
server.close();
