const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Dates.js", "utf8"), context);

const today = "2026-11-23";

test("parses today, tomorrow and ISO dates out of a title", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.parseDue("Buy milk tomorrow", today))), {
    title: "Buy milk", due: "2026-11-24",
  });
  assert.deepEqual(JSON.parse(JSON.stringify(context.parseDue("Pay rent today", today))), {
    title: "Pay rent", due: today,
  });
  assert.deepEqual(JSON.parse(JSON.stringify(context.parseDue("Submit report 2026-11-30", today))), {
    title: "Submit report", due: "2026-11-30",
  });
  assert.deepEqual(JSON.parse(JSON.stringify(context.parseDue("No date here", today))), {
    title: "No date here", due: null,
  });
});

test("next weekday is always in the future", () => {
  assert.equal(context.parseDue("Standup next Mon", today).due, "2026-11-30");
  assert.equal(context.parseDue("Review next wednesday", today).due, "2026-11-25");
  assert.equal(context.weekday("nope", today), null);
});

test("invalid dates and long titles are bounded", () => {
  assert.equal(context.validDay("2026-02-30"), false);
  assert.equal(context.validDay("tomorrow"), false);
  const result = context.parseDue("x".repeat(900) + " tomorrow", today);
  assert.equal(result.title.length, 500);
  assert.equal(result.due, "2026-11-24");
});

test("labels distinguish today, tomorrow and overdue", () => {
  assert.equal(context.dueLabel(today, today), "Today");
  assert.equal(context.dueLabel("2026-11-24", today), "Tomorrow");
  assert.equal(context.dueLabel("2026-11-22", today), "Overdue · 2026-11-22");
  assert.equal(context.dueLabel("2026-12-01", today).length > 0, true);
  assert.equal(context.dueLabel(null, today), "");
});
