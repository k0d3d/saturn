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
