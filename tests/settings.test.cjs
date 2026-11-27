const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Settings.js", "utf8"), context);

test("fresh settings enable a lean DeepSeek schedule", () => {
  const value = JSON.parse(JSON.stringify(context.fresh()));
  assert.deepEqual(value, {
    llm: {
      enabled: true,
      model: "opencode/deepseek-v4.1-flash-free",
      hours: [9, 18],
      batch: 20,
      timeout: 120,
      prompt: "",
    },
  });
});

test("normalise fills missing and invalid fields but keeps valid choices", () => {
  const value = JSON.parse(JSON.stringify(context.normalise({
    llm: {model: "custom/model", hours: [7, 99], batch: 5, nonsense: true},
  })));
  assert.equal(value.llm.enabled, true);
  assert.equal(value.llm.model, "custom/model");
  assert.deepEqual(value.llm.hours, [9, 18]);
  assert.equal(value.llm.batch, 5);
  assert.equal(value.llm.timeout, 120);
  assert.deepEqual(JSON.parse(JSON.stringify(context.normalise(null))).llm.hours, [9, 18]);
  assert.equal(context.normalise({llm: null}).llm.enabled, true);
});

test("an empty schedule is a valid way to disable the pass", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.normalise({llm: {hours: []}}))).llm.hours, []);
});

test("fresh and migrated workspaces both carry settings", () => {
  const logic = vm.createContext({});
  vm.runInContext(fs.readFileSync("Logic.js", "utf8"), logic);
  const expected = JSON.parse(JSON.stringify(context.fresh()));
  assert.deepEqual(JSON.parse(JSON.stringify(logic.fresh().settings)), expected);
  const migrated = logic.migrate(logic.fresh());
  assert.deepEqual(JSON.parse(JSON.stringify(migrated.settings)), expected);
});

test("the shell exposes settings through the data command", () => {
  const service = fs.readFileSync("Service.qml", "utf8");
  assert.match(service, /import "Settings\.js" as Settings/);
  assert.match(service, /if \(cmd === "settings"\) return JSON\.stringify\(root\.workspace\.settings \|\| \{\}\);/);
  assert.match(service, /if \(cmd === "settings-set"\)/);
});
