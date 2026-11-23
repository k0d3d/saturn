const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Logic.js", "utf8"), context);
test("old workspaces migrate and running sessions resume paused", () => {
  const state = context.fresh();
  state.focus.running = true;
  const restored = context.parse(JSON.stringify(state));
  assert.equal(restored.focus.running, false);
  assert.equal(restored.version, 2);
  assert.equal(restored.focus.running, false);
});
test("v1 workspaces gain dated, archivable tasks and empty v2 collections", () => {
  const fixture = JSON.parse(
    fs.readFileSync("tests/fixtures/v1-workspace.json", "utf8"),
  );
  const state = context.parse(JSON.stringify(fixture));
  assert.equal(state.version, 2);
  assert.equal(state.tasks.length, 2);
  assert.equal(state.tasks[0].due, null);
  assert.equal(state.tasks[0].createdAt, 0);
  assert.equal(state.tasks[0].archived, false);
  assert.equal(JSON.stringify(state.tasks[0].tags), "[]");
  assert.equal(state.tasks[1].createdAt, 1795416635190);
  assert.equal(JSON.stringify(state.notesV2), "[]");
  assert.equal(JSON.stringify(state.sync), '{"providers":{},"conflicts":[],"tombstones":[]}');
  assert.equal(JSON.stringify(state.insights), "{}");
  assert.equal(state.messageKeyOnly, false);
  assert.equal(state.focus.running, false);
});
test("v2 fields are validated and invalid due dates are dropped", () => {
  const state = context.fresh();
  state.tasks.push({ id: "t", title: "Tomorrow", done: false, completedAt: 0 });
  state.notesV2.push({ id: "n", title: "Note", body: "Body", date: "2026-11-24", tags: ["work"] });
  let restored = context.parse(JSON.stringify(state));
  assert.equal(restored.tasks[0].due, null);
  assert.equal(restored.notesV2[0].date, "2026-11-24");
  state.tasks[0].due = "2026-11-25";
  restored = context.parse(JSON.stringify(state));
  assert.equal(restored.tasks[0].due, "2026-11-25");
  state.tasks[0].due = "tomorrow";
  assert.equal(context.parse(JSON.stringify(state)).tasks[0].due, null);
  state.tasks[0].archived = "yes";
  assert.throws(() => context.parse(JSON.stringify(state)));
});
test("task views keep completed work visible and hide archived items", () => {
  const today = "2026-11-23";
  const tasks = [
    { id: "a", title: "Today", done: false, completedAt: 0, due: today, archived: false },
    { id: "b", title: "Tomorrow", done: false, completedAt: 0, due: "2026-11-24", archived: false },
    { id: "c", title: "Undated", done: false, completedAt: 0, due: null, archived: false },
    { id: "d", title: "Done", done: true, completedAt: 20, due: today, archived: false },
    { id: "e", title: "Old done", done: true, completedAt: 10, due: null, archived: false },
    { id: "f", title: "Archived", done: false, completedAt: 0, due: today, archived: true },
  ];
  const ids = (view) => context.tasksInView(tasks, view, today).map((t) => t.id).join(",");
  assert.equal(ids("Today"), "a,c");
  assert.equal(ids("Upcoming"), "b");
  assert.equal(ids("All"), "a,b,c");
  assert.equal(ids("Completed"), "d,e");
  assert.equal(ids("Archive"), "f");
});

test("own writes are ignored but external edits are adopted", () => {
  const state = context.fresh();
  const payload = context.serialize(state);
  assert.equal(context.shouldAdopt(payload, payload, true, ""), false);
  assert.equal(context.shouldAdopt(payload + " ", payload, true, ""), true);
  assert.equal(context.shouldAdopt(payload, payload, false, ""), true);
  assert.equal(context.shouldAdopt(payload, payload, true, "error"), true);
  assert.equal(context.needsWrite(state, payload), false);
  state.tasks.push({ id: "t", title: "New", done: false, completedAt: 0 });
  assert.equal(context.needsWrite(state, payload), true);
});
test("an external edit wins over a pending local save", () => {
  const original = context.fresh();
  const persisted = context.serialize(original);
  const local = context.fresh();
  local.tasks.push({ id: "local", title: "Local edit", done: false, completedAt: 0 });
  assert.equal(context.needsWrite(local, persisted), true); // save queued
  const external = context.fresh();
  external.tasks.push({ id: "agent", title: "Agent edit", done: false, completedAt: 0 });
  const incoming = context.serialize(external);
  assert.equal(context.shouldAdopt(incoming, persisted, true, ""), true);
  const adopted = context.parse(incoming);
  assert.equal(context.needsWrite(adopted, context.serialize(adopted)), false); // queued flush is a no-op
  assert.equal(adopted.tasks[0].id, "agent");
});
test("legacy task source is preserved but no longer selects a provider", () => {
  const state = context.fresh();
  state.taskSource = "todoist";
  const restored = context.parse(JSON.stringify(state));
  assert.equal(restored.taskSource, "todoist"); // kept as harmless legacy metadata
});
test("suspend never counts as active focus time", () => {
  const state = context.fresh();
  state.focus.running = true;
  assert.equal(context.advance(state, 90, Date.now()), "paused");
  assert.equal(state.focus.elapsed, 0);
  assert.equal(state.focus.running, false);
});
test("focus completion stops precisely and records active time", () => {
  const state = context.fresh();
  state.focus.duration = 2;
  state.focus.running = true;
  assert.equal(context.advance(state, 3, Date.now()), "finished");
  assert.equal(state.focus.elapsed, 2);
  assert.equal(state.focus.running, false);
  assert.equal(Object.values(state.activity)[0], 2);
});
test("site build keeps helper code and credentials outside the public output", () => {
  const { execFileSync } = require("node:child_process");
  execFileSync(process.execPath, ["scripts/build-site.cjs"]);
  const files = fs.readdirSync("dist/site", { recursive: true });
  assert(files.includes("install.sh"));
  assert(files.includes("index.html"));
  assert(
    !files.some((file) =>
      /\.py$|\.qml$|todoist\.json|workspace\.json|\.env/.test(file),
    ),
  );
});
test("every public HTML page includes the creator's social handles", () => {
  const pages = fs
    .readdirSync("dist/site")
    .filter((file) => file.endsWith(".html"));
  assert(pages.includes("index.html"));
  assert(pages.includes("404.html"));
  assert(!pages.includes("_footer.html"));
  for (const page of pages) {
    const html = fs.readFileSync(`dist/site/${page}`, "utf8");
    for (const url of [
      "https://twitter.com/kostahantzis",
      "https://www.linkedin.com/in/kostahantzis/",
      "https://www.instagram.com/kostahantzis/",
      "https://www.youtube.com/@kostahantzis_",
      "https://mentorpass.co/kostahantzis",
    ])
      assert(html.includes(url), `${page} is missing ${url}`);
    assert(!html.includes("<!-- SITE_FOOTER -->"));
  }
});

test("provider choices persist while unknown values are rejected", () => {
  const state = context.fresh();
  for (const source of ["hey", "gmail", "outlook", "imap", "off"]) {
    state.mailSource=source; state.calendarSource="google";
    assert.equal(context.parse(JSON.stringify(state)).mailSource,source);
  }
  state.mailSource="invalid";
  assert.throws(() => context.parse(JSON.stringify(state)));
});
