const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const service = fs.readFileSync("Service.qml", "utf8");
const dashboard = fs.readFileSync("Dashboard.qml", "utf8");

test("panel navigation lives in a local per-screen ui-state file", () => {
  assert.match(service, /property var uiState: \(\{\}\)/);
  assert.match(service, /FileView \{[\s\S]*?id: uiStorage[\s\S]*?ui-state\.json/);
  assert.match(service, /function saveUiState\(screenName, state\)/);
  assert.match(service, /root\.uiState = next;\s*uiStorage\.setText\(JSON\.stringify\(next\)\)/);
  assert.match(service, /function uiStateFor\(screenName\)[\s\S]*?root\.uiState\[String\(screenName \|\| ""\)\]/);
});

test("the close control saves the current card and its navigation state", () => {
  const close = dashboard.slice(dashboard.indexOf("function close()"), dashboard.indexOf("function moveDay"));
  assert.match(close, /dash\.saveState\(\)/);
  const save = dashboard.slice(dashboard.indexOf("function saveState()"), dashboard.indexOf("function close()"));
  for (const key of ["focusedCard", "notesView", "openNoteId", "taskView", "selectedTaskId", "noteDay"]) {
    assert.match(save, new RegExp(key));
  }
});

test("reopening restores the saved view without handlers resetting it", () => {
  assert.match(dashboard, /function restoreState\(\)/);
  assert.match(dashboard, /restoringState/);
  const visible = dashboard.slice(dashboard.indexOf("onVisibleChanged:"), dashboard.indexOf("onFrostedChanged:"));
  assert.match(visible, /dash\.saveState\(\)/);
  assert.match(visible, /dash\.restoreState\(\)/);
});
