const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const pathsOf = (name) => {
  const svg = fs.readFileSync(`assets/${name}`, "utf8");
  return svg.match(/<path[^>]*\/>/g) || [];
};

const original = pathsOf("saturn.svg");

test("layered mark assets partition the original SVG exactly", () => {
  const layers = ["saturn-back.svg", "saturn-planet.svg", "saturn-ring.svg"];
  const combined = layers.flatMap(pathsOf);
  assert.equal(combined.length, 10);
  assert.equal(new Set(combined).size, 10);
  assert.ok(combined.every((p) => original.includes(p)));
  assert.deepEqual(pathsOf("saturn-back.svg").length, 2);
  assert.deepEqual(pathsOf("saturn-planet.svg").length, 1);
  assert.deepEqual(pathsOf("saturn-ring.svg").length, 7);
});

test("each star dot is its own animatable asset", () => {
  const stars = [1, 2, 3, 4, 5].map((n) => pathsOf(`saturn-star-${n}.svg`));
  assert.deepEqual(stars.map((s) => s.length), [1, 1, 1, 1, 1]);
  assert.deepEqual(
    [...stars.flat(), ...pathsOf("saturn-ring.svg"), ...pathsOf("saturn-back.svg"), ...pathsOf("saturn-planet.svg")].sort(),
    [...original].sort()
  );
});

test("ring layers counter-rotate and stars twinkle on staggered cycles", () => {
  const mark = fs.readFileSync("SaturnMark.qml", "utf8");
  assert.match(mark, /saturn-back\.svg/);
  assert.match(mark, /saturn-planet\.svg/);
  assert.match(mark, /saturn-ring\.svg/);
  assert.match(mark, /saturn-star-\" \+ \(index \+ 1\)/);
  // Back band turns one way, front band the other, each in a looping sequence.
  assert.match(mark, /SequentialAnimation[\s\S]*?loops: Animation\.Infinite[\s\S]*?running: true/);
  assert.match(mark, /from: -8; to: 8[\s\S]*?duration: Style\.duration\(3400\)/);
  assert.match(mark, /from: 8; to: -8[\s\S]*?duration: Style\.duration\(2600\)/);
  assert.match(mark, /Repeater[\s\S]*?model: 5[\s\S]*?property: "opacity"/);
  assert.match(mark, /duration: Style\.duration\(650 \+ index \* 185\)/);
  assert.match(mark, /target: mark; property: "scale"/);
  assert.doesNotMatch(mark, /alternate: true/);
});

test("the header swaps its static raster for the animated mark", () => {
  const dash = fs.readFileSync("Dashboard.qml", "utf8");
  assert.match(dash, /SaturnMark \{[\s\S]*?size: 46[\s\S]*?active: dash\.store\.focusState && dash\.store\.focusState\.running/);
  assert.doesNotMatch(dash, /Image \{ Layout\.preferredWidth: 46; Layout\.preferredHeight: 46; source: Qt\.resolvedUrl\("assets\/saturn\.png"\)/);
});
