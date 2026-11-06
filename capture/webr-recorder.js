// Recorder in place of the in-browser R bridge: same exports, no R.
const loadedDatasets = new Map();
window.__cap = { json: {}, code: [] };
export async function initWebR() { return {}; }
export async function loadXptFile(_buf, name) {
  const info = window.__meta[name.toLowerCase()];
  loadedDatasets.set(info.name, info); return info;
}
export async function executeR(code) { window.__cap.code.push(code); return { success: true, result: '{}' }; }
export async function getDataFrameAsJSON() { return []; }
export function isInitialized() { return true; }
export function getLoadedDatasets() { return Array.from(loadedDatasets.values()); }
export async function loadEngine() {}
export async function setJsonVariable(n, s) { window.__cap.json[n] = s; }
