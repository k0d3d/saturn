const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Visual.js", "utf8"), context);
const plain = (value) => JSON.parse(JSON.stringify(value));

test("workspace rectangles fit and never overlap at desktop and narrow widths", () => {
  for (const width of [720, 1100, 1800, 2500]) {
    const layout = context.grid(width, 880);
    const boxes = Object.values(layout.cards);
    for (const a of boxes) {
      assert(a.x >= 0 && a.y >= 0 && a.width > 0 && a.height >= 200);
      assert(a.x + a.width <= width + 0.01);
      assert(a.y + a.height <= layout.height + 0.01);
      for (const b of boxes) if (a !== b)
        assert(a.x + a.width <= b.x || b.x + b.width <= a.x ||
          a.y + a.height <= b.y || b.y + b.height <= a.y);
    }
    assert(layout.cards.tasks.height >= layout.cards.focus.height);
  }
});

test("volume is banded and bounded", () => {
  assert.equal(context.volume(0), 0);
  assert.equal(context.volume(2), 1);
  assert.equal(context.volume(7), 2);
  assert.equal(context.volume(50), 3);
});

test("attention is urgency, not volume", () => {
  assert.deepEqual(plain(context.attention([], "2026-11-26", 40)),
    {level: 1, count: 40, reason: "unread"});
  const tasks = [
    {due: "2026-11-25", done: false, archived: false},
    {due: "2026-11-26", done: false, archived: false},
    {due: "2026-11-20", done: true, archived: false},
    {due: "2026-11-20", done: false, archived: true},
  ];
  assert.deepEqual(plain(context.attention(tasks, "2026-11-26", 0)),
    {level: 2, count: 1, reason: "overdue"});
  assert.deepEqual(plain(context.attention(tasks.slice(1), "2026-11-26", 0)),
    {level: 1, count: 1, reason: "today"});
});

test("day notes exclude archived and daily notes, pins first", () => {
  const state = {
    notesV2: [
      {id: "a", title: "Late idea", date: "2026-11-26", updatedAt: 30, pinned: false, archived: false},
      {id: "b", title: "Pinned plan", date: "2026-11-26", updatedAt: 10, pinned: true, archived: false},
      {id: "c", title: "Archived", date: "2026-11-26", updatedAt: 40, archived: true},
      {id: "d", title: "Other day", date: "2026-11-25", updatedAt: 50},
    ],
    notes: {"2026-11-26": "Daily note"},
  };
  assert.deepEqual(plain(context.forDay(state, "2026-11-26")).map(n => n.id), ["b", "a"]);
  assert.deepEqual(plain(context.forDay(state, "bad-date")), []);
});
