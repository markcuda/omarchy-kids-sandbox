#!/bin/bash
# SPEC.md R-BAR-2, I-5/I-6; #153: actual model, status reader, and keyboard handlers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QML=${QML_PATH:-$ROOT/share/bar/KidsModule.qml}
NODE_BIN=${NODE_BIN:-node}
command -v "$NODE_BIN" >/dev/null 2>&1 || {
  echo 'SKIP bar-menu-rows-test.sh: node not found'
  exit 0
}

QML_PATH="$QML" "$NODE_BIN" <<'NODE'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const qml = fs.readFileSync(process.env.QML_PATH, 'utf8');

function extractFunction(source, name) {
  const start = source.indexOf(`function ${name}(`);
  if (start < 0) throw new Error(`missing ${name}`);
  const bodyStart = source.indexOf('{', start);
  let depth = 0;
  for (let i = bodyStart; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const makeMenuRows = extractFunction(qml, 'makeMenuRows');
const requestCountFromData = extractFunction(qml, 'requestCountFromData');
const model = vm.runInNewContext(`(${makeMenuRows})`);
const rows = model([
  { kid: 'kid-test', initial: 'T', slug: 'test', minutesLeft: 7, paused: false },
  { kid: 'kid-cy', initial: 'C', slug: 'cy', minutesLeft: 592, paused: true }
], 2, 15);
if (rows.length !== 6) throw new Error('expected two rows per child plus requests/open');
if (rows[0].actionLabel !== 'Give 15 more' || rows[0].detailLabel !== 'T test · live · 7 min') throw new Error('live grant row changed');
if (rows[3].actionLabel !== 'End session' || rows[3].detailLabel !== 'C cy · paused · 592 min') throw new Error('paused end row changed');
if (rows[4].label !== 'Open requests (2)' || rows[5].label !== 'Open Kids Mode') throw new Error('ordinary rows changed');

const visibilityLine = qml.split('\n').find((line) => line.includes('rowDelegate.modelData.actionLabel !== undefined'));
if (!visibilityLine) throw new Error('missing actual action-row visibility expression');
const expression = visibilityLine.split('visible: ')[1].trim();
const visible = (row) => vm.runInNewContext(expression, { rowDelegate: { modelData: row } });
if (!visible(rows[0]) || !visible(rows[3]) || !visible(rows[4]) || !visible(rows[5])) throw new Error('row visibility does not cover all menu kinds');
if (visible({ actionLabel: 'Give 15 more', detailLabel: 'T test · live · 7 min' }) !== true) throw new Error('action row hidden');
if (visible({ label: 'Open Kids Mode' }) !== true) throw new Error('ordinary row hidden');

// Run the actual reader with owned input, retaining one open menu across updates.
let statusText = '';
let readFails = false;
const launches = [];
const root = {
  liveKids: [], openRequestCount: -1, grantMinutes: 15,
  cursorIndex: 0, hasFile: false, opened: true,
  kidsBin: '/fixture/kids', barCtlBin: '/fixture/bar',
  runDetached(command) { launches.push(Array.from(command)); },
  close() { this.opened = false; }
};
const context = vm.createContext({
  root,
  statusFile: { text() { if (readFails) throw new Error('missing fixture'); return statusText; } }
});
for (const name of ['makeMenuRows', 'requestCountFromData', 'reloadStatus', 'kidSlug', 'kidInitial', 'activateRow']) {
  root[name] = vm.runInContext(`(${extractFunction(qml, name)})`, context);
  context[name] = root[name];
}
Object.defineProperty(root, 'menuRows', {
  get() { return root.makeMenuRows(root.liveKids, root.openRequestCount, root.grantMinutes); }
});
const moveMatch = qml.match(/onMoveRequested:\s*(function \(dx, dy\) \{[^]*?^            \})/m);
assert(moveMatch, 'actual movement handler is present');
const move = vm.runInContext(`(${moveMatch[1]})`, context);
function handler(name) {
  const match = qml.match(new RegExp('^\\s*' + name + ': (.+)$', 'm'));
  assert(match, `actual ${name} handler is present`);
  return vm.runInContext(`() => { ${match[1]} }`, context);
}
const activate = handler('onActivateRequested');
const enter = handler('onReturnRequested');
const escape = handler('onCloseRequested');
const populated = JSON.stringify({ kids: [{ kid: 'kid-cy', live: true, paused: false, minutes_left: 17 }], open_requests: 2 });
const states = [
  ['missing', '', -1], ['empty', '', -1], ['malformed', '{', -1],
  ['scalar-zero', '0', -1], ['valid-empty', '{"kids":[]}', -1],
  ['zero', '{"kids":[],"open_requests":0}', 0],
  ['positive', '{"kids":[],"open_requests":2}', 2],
  ['negative', '{"kids":[],"open_requests":-1}', -1],
  ['fractional', '{"kids":[],"open_requests":1.5}', -1]
];
const badgeLine = qml.split('\n').find((line) => line.trim().startsWith('visible: root.openRequestCount > 0 ||'));
assert(badgeLine, 'actual badge visibility binding is present');
const badgeExpression = badgeLine.trim().slice('visible: '.length);
const badgeTextLine = qml.split('\n').find((line) => line.trim().startsWith('text: root.openRequestCount < 0'));
assert(badgeTextLine, 'actual badge text binding is present');
const badgeTextExpression = badgeTextLine.trim().slice('text: '.length);
const mainVisibility = qml.split('\n').find((line) => line.trim().startsWith('visible: rowDelegate.modelData.actionLabel'));
const detailVisibility = qml.split('\n').find((line) => line.trim() === 'visible: rowDelegate.modelData.detailLabel !== undefined');
const mainText = qml.split('\n').find((line) => line.trim() === 'text: rowDelegate.modelData.actionLabel || rowDelegate.modelData.label');
const rowHeight = qml.split('\n').find((line) => line.trim().startsWith('height: rowDelegate.modelData.kind === "grant"'));
assert(mainVisibility && detailVisibility && mainText && rowHeight, 'actual request row bindings are present');
const rowContext = (row) => ({ rowDelegate: { modelData: row } });
const widgetLine = qml.split('\n').find((line) => line.trim().startsWith('visible: root.hasFile &&'));
assert(widgetLine, 'actual widget visibility binding is present');
const widgetExpression = widgetLine.trim().slice('visible: '.length);
for (const [kind, nextText, expectedCount] of states) {
  readFails = false;
  statusText = populated;
  root.opened = true;
  root.reloadStatus();
  root.cursorIndex = root.menuRows.length - 1;
  assert.strictEqual(root.cursorIndex, 3, 'fixture selects the last of four rows');
  readFails = kind === 'missing';
  statusText = nextText;
  root.reloadStatus();
  assert.strictEqual(root.hasFile, kind !== 'missing' && kind !== 'empty' && kind !== 'malformed');
  assert.strictEqual(root.openRequestCount, expectedCount, `${kind} count state`);
  assert.strictEqual(root.liveKids.length, 0, `${kind} hides child controls`);
  assert.deepStrictEqual(Array.from(root.menuRows, row => row.kind), ['requests', 'open']);
  const requestRow = root.menuRows[0];
  assert.strictEqual(requestRow.label, expectedCount >= 0 ? `Open requests (${expectedCount})` : undefined, `${kind} menu label`);
  assert.strictEqual(requestRow.actionLabel, expectedCount < 0 ? 'Open requests' : undefined, `${kind} menu main text`);
  assert.strictEqual(requestRow.detailLabel, expectedCount < 0 ? 'Count unavailable' : undefined, `${kind} menu detail`);
  assert.strictEqual(vm.runInNewContext(mainVisibility.trim().slice('visible: '.length), rowContext(requestRow)), true, `${kind} main text visible`);
  assert.strictEqual(vm.runInNewContext(detailVisibility.trim().slice('visible: '.length), rowContext(requestRow)), expectedCount < 0, `${kind} detail visibility`);
  assert.strictEqual(vm.runInNewContext(mainText.trim().slice('text: '.length), rowContext(requestRow)), expectedCount < 0 ? 'Open requests' : `Open requests (${expectedCount})`, `${kind} main text`);
  assert.strictEqual(vm.runInNewContext(rowHeight.trim().slice('height: '.length), rowContext(requestRow)), expectedCount < 0 ? 44 : 28, `${kind} row height`);
  assert.strictEqual(vm.runInNewContext(badgeExpression, { root }), expectedCount !== 0, `${kind} badge state`);
  assert.strictEqual(vm.runInNewContext(badgeTextExpression, { root }), expectedCount < 0 ? '?' : String(expectedCount), `${kind} badge text`);
  assert.strictEqual(vm.runInNewContext(widgetExpression, { root }), root.hasFile && (root.liveKids.length > 0 || expectedCount !== 0), `${kind} widget visibility`);
  assert(root.cursorIndex >= 0 && root.cursorIndex < root.menuRows.length, `${kind} keeps a visible selection`);
  assert.strictEqual(root.opened, true, `${kind} does not reopen or close the menu`);
  move(0, -1);
  assert.strictEqual(root.menuRows[root.cursorIndex].kind, 'open', `${kind} Up wraps to Open Kids Mode`);
  move(0, 1);
  assert.strictEqual(root.menuRows[root.cursorIndex].kind, 'requests', `${kind} Down wraps to requests`);
  move(1, 0);
  assert.strictEqual(root.cursorIndex, 0, 'horizontal movement preserves selection');
  move(0, 1);
  root.reloadStatus();
  assert.strictEqual(root.cursorIndex, 1, 'repeated refresh preserves a still-valid selection');
  activate();
  assert.deepStrictEqual(launches.pop(), ['/fixture/kids'], 'activation targets the visible ordinary row');
  root.opened = true;
  enter();
  assert.deepStrictEqual(launches.pop(), ['/fixture/kids'], 'Enter targets the visible ordinary row');
  root.opened = true;
  readFails = false;
  statusText = populated;
  root.reloadStatus();
  assert.strictEqual(root.cursorIndex, 1, 'recreation retains the current valid index, not the stale old index');
  assert.strictEqual(root.menuRows.length, 4, 'recreation restores child rows');
  escape();
  assert.strictEqual(root.opened, false, 'Escape closes the same menu');
  assert.strictEqual(launches.length, 0, 'no child action was launched');
}
console.log('bar-menu-rows-test: PASS');
NODE
