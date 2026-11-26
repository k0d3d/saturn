const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Notes.js", "utf8"), context);

const plain = (value) => JSON.parse(JSON.stringify(value));

test("new notes are dated, tagged, unpinned and bounded", () => {
  const note = plain(context.make({title: "  Saturn plan  ", body: "x".repeat(30000),
    tags: "#Work, work, HOME, ideas", date: "2026-11-24"}, 1000));
  assert.equal(note.title, "Saturn plan");
  assert.equal(note.body.length, 20000);
  assert.deepEqual(note.tags, ["work", "home", "ideas"]);
  assert.equal(note.date, "2026-11-24");
  assert.equal(note.archived, false);
  assert.equal(note.pinned, false);
  assert.equal(note.createdAt, 1000);
});

test("invalid dates are dropped and updates keep the id", () => {
  const original = plain(context.make({title: "Note", date: "tomorrow"}, 1000));
  assert.equal(original.date, null);
  const updated = plain(context.update(original, {title: "Renamed", tags: "a,b", date: "2026-11-25"}, 2000));
  assert.equal(updated.id, original.id);
  assert.equal(updated.title, "Renamed");
  assert.equal(updated.date, "2026-11-25");
  assert.equal(updated.updatedAt, 2000);
});

test("search spans library and daily notes, pins first, and bounds results", () => {
  const state = {
    notesV2: [
      {id: "a", title: "Grok voice", body: "voice notes", tags: ["ai"], date: "2026-11-20", archived: false, pinned: false, updatedAt: 20},
      {id: "b", title: "Pinned idea", body: "voice setup", tags: [], date: null, archived: false, pinned: true, updatedAt: 10},
      {id: "c", title: "Archived", body: "voice old", tags: [], date: null, archived: true, pinned: false, updatedAt: 5},
    ],
    notes: {"2026-11-23": "Daily voice note", "2026-11-22": "Unrelated"},
  };
  const all = plain(context.search(state, "voice", 50));
  assert.deepEqual(all.map((n) => n.id), ["b", context.dailyId("2026-11-23"), "a", "c"]);
  assert.equal(all[0].source, "library");
  assert.equal(all[1].source, "daily");
  assert.equal(plain(context.search(state, "voice", 1)).length, 1);
  assert.equal(plain(context.search(state, "nothing matches")).length, 0);
});

test("daily ids round-trip and excerpts are plain text", () => {
  assert.equal(context.isDaily(context.dailyId("2026-11-23")), true);
  assert.equal(context.isDaily("abc"), false);
  assert.equal(context.excerpt("a  b\nc", 80), "a b c");
});

test("plain strips wiki links and heading marks for previews", () => {
  assert.equal(context.plain("## Omarchy\n- [[Allow Pinned messages on Omarchy]]\n- [[Change icon on Saturn when Focusing]]"),
    "Omarchy - Allow Pinned messages on Omarchy - Change icon on Saturn when Focusing");
  assert.equal(context.plain(""), "");
});

test("reading lines split wiki references into readable label pills", () => {
  const lines = plain(context.readingLines("## Omarchy\nTry [[Task A]] and [[Note B]].\nNext line"));
  assert.deepEqual(lines, [
    {heading: true, parts: [{text: "Omarchy"}]},
    {heading: false, parts: [{text: "Try "}, {reference: "Task A"}, {text: " and "}, {reference: "Note B"}, {text: "."}]},
    {heading: false, parts: [{text: "Next line"}]},
  ]);
  assert.deepEqual(plain(context.readingLines("")), [{heading: false, parts: [{text: "No text yet."}]}]);
});

test("board note dates are relative to today, with clear older and undated labels", () => {
  const today = "2026-11-26";
  assert.equal(context.boardDate("2026-11-26", today), "Today");
  assert.equal(context.boardDate("2026-11-25", today), "Yesterday");
  assert.equal(context.boardDate("2026-11-23", today), "3 days ago");
  assert.equal(context.boardDate("2026-11-19", today), "19 Nov");
  assert.equal(context.boardDate("2025-11-19", today), "19 Nov 2025");
  assert.equal(context.boardDate("2026-11-27", today), "Tomorrow");
  assert.equal(context.boardDate(null, today), "Undated");
});

test("daily notes get relative titles when the board knows today", () => {
  const state = {notesV2: [], notes: {"2026-11-26": "today", "2026-11-25": "yesterday"}, archived: false};
  const results = plain(context.search(state, "", 20, "2026-11-26"));
  assert.deepEqual(results.map((n) => n.title), ["Daily note · Today", "Daily note · Yesterday"]);
});

test("daily notes open in the embedded editor rather than the daily pane", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  const pane = fs.readFileSync("NotesPane.qml", "utf8");
  const viewNote = dashboard.slice(dashboard.indexOf("function viewNote"), dashboard.indexOf("function returnToBoard"));
  assert.doesNotMatch(viewNote, /isDaily/);
  assert.match(pane, /store\.setDailyNote\(/);
  assert.match(pane, /store\.dailyNoteBody\(/);
});

test("task detail actions form one quiet group without a tab-like hover", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  const action = dashboard.slice(dashboard.indexOf("component ActionButton"), dashboard.indexOf("component Dial"));
  assert.doesNotMatch(action, /theme\.alpha\(theme\.accent/);
  const row = dashboard.slice(dashboard.indexOf('text: "Focus 25m"'), dashboard.indexOf('role: "focus"'));
  assert.doesNotMatch(row, /Item \{ Layout\.fillWidth: true \}/);
});

test("both note boards use the shared relative date formatter", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  const library = fs.readFileSync("NotesPane.qml", "utf8");
  assert.match(dashboard, /Notes\.boardDate\(noteCard\.modelData\.date,\s*dash\.store\.today\)/);
  assert.match(library, /Notes\.boardDate\(card\.modelData\.date,\s*pane\.store\.today\)/);
});

test("the daily editor has no embedded library grid and library is the cross-date board", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  const library = fs.readFileSync("NotesPane.qml", "utf8");
  assert.doesNotMatch(dashboard, /model:\s*dash\.boardNotes/);
  assert.match(library, /model:\s*pane\.results/);
  assert.match(dashboard, /createNoteForDay\(dash\.store\.today\)/);
});

test("fullscreen dashboard does not request exclusive keyboard focus", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  assert.doesNotMatch(dashboard, /WlrKeyboardFocus\.Exclusive/);
});

test("opening Saturn on another monitor closes the prior overlay", () => {
  const window = fs.readFileSync("OwlWindow.qml", "utf8");
  assert.match(window, /function open\(\)[\s\S]*?store\.closeOtherWindows\(win\)/);
});

test("workspace changes explicitly recheck the opening workspace", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  assert.match(dashboard, /onRawEvent\(event\)[\s\S]*?workspacev2[\s\S]*?workspaceCheck\.restart\(\)/);
});

test("switch cards center their icon and caption group", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  assert.match(dashboard, /id:\s*miniContent[\s\S]*?anchors\.centerIn:\s*parent/);
});

test("Notepad header separates view tabs, day navigation, and the new-note action", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  assert.match(dashboard, /component NoteTab: AbstractButton/);
  assert.match(dashboard, /component DayArrow: AbstractButton/);
  assert.match(dashboard, /component NewNoteButton: AbstractButton/);
  assert.doesNotMatch(dashboard, /NoteTab \{ text: "(Write|Board)"/);
  assert.match(dashboard, /DayArrow \{[^}]*iconName: "chevron-left"/);
  assert.match(dashboard, /DayArrow \{[^}]*iconName: "chevron-right"/);
  assert.match(dashboard, /NewNoteButton \{[^}]*onClicked: dash\.createNoteForDay\(dash\.store\.today\)/);
});

test("expanded Notepad aligns its header with the close control", () => {
  const dashboard = fs.readFileSync("Dashboard.qml", "utf8");
  const notepad = dashboard.slice(dashboard.indexOf('role: "notes"'), dashboard.indexOf('role: "events"'));
  assert.match(notepad, /anchors\.topMargin:\s*dash\.focusedCard === "notes" \? 10 : 32/);
  assert.match(notepad, /Layout\.topMargin:\s*dash\.notesView === "board" \? 10 : 0/);
});
