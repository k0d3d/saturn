const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const context = vm.createContext({});
vm.runInContext(fs.readFileSync("Tags.js", "utf8"), context);

test("pulls meaningful words from a title into lowercase tags", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Review Q3 Roadmap with Priya"))),
    ["review", "q3", "roadmap", "priya"]);
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Fix the leaky Faucet in Kitchen"))),
    ["fix", "leaky", "faucet", "kitchen"]);
});

test("drops function words, date words and numbers", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("a an the and tomorrow"))), []);
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Pay 123 rent today"))), ["pay", "rent"]);
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Call dentist next Mon"))), ["call", "dentist"]);
});

test("keeps hashtag words and unicode letters", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Ship #launch notes café"))),
    ["ship", "launch", "notes", "café"]);
});

test("deduplicates and caps the tag count", () => {
  const many = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu".split(" ").join(" ");
  const result = context.fromTitle(many);
  assert.equal(result.length, 8);
  assert.equal(new Set(result).size, 8);
  assert.deepEqual(JSON.parse(JSON.stringify(context.fromTitle("Milk milk MILK milk"))), ["milk"]);
});

test("merging keeps curated tags and adds new title words", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(context.mergeTags(["curated"], "Review Roadmap with Priya"))),
    ["curated", "review", "roadmap", "priya"]);
  assert.deepEqual(JSON.parse(JSON.stringify(context.mergeTags(["roadmap"], "Review Roadmap"))),
    ["roadmap", "review"]);
});

test("both add paths use the deterministic tag extractor", () => {
  const service = fs.readFileSync("Service.qml", "utf8");
  assert.match(service, /tags: Tags\.fromTitle\(parsed\.title\)/);
  assert.match(service, /t\.tags = Tags\.mergeTags\(t\.tags, text\);/);
  const api = fs.readFileSync("scripts/workspace_api.py", "utf8");
  assert.match(api, /'tags': tags_from_title\(title\)/);
});
