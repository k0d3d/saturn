const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const vm = require("node:vm");

const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync("Slogans.js", "utf8"), context);

test("the rotating slogans are unique, non-empty and attributed", () => {
  const lines = context.lines;
  assert.equal(lines.length, 20);
  assert.equal(new Set(lines).size, lines.length);
  for (const line of lines) {
    assert.ok(line.trim().length > 0);
    assert.ok(line.length <= 90, line);
    if (line.startsWith("“")) {
      const [quote, author] = line.split(" — ");
      assert.ok(quote.endsWith("”"), line);
      assert.ok(author && author.length > 1, line);
    }
  }
});
