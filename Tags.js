// Instant, deterministic tags from a task title. The LLM pass in
// scripts/llm_tags.py refines these later; this first pass is synchronous so
// a new task is tagged the moment it is added, with no model latency.
var STOPWORDS = ("a an the and or but if then so to of in on at by for with from "
    + "is are was were be been being do does did done have has had i me my we our "
    + "you your he she it its they their this that these those will would can could "
    + "should may might must not no yes please about into over under again more most "
    + "some any all as just also up out off down new now today tomorrow yesterday "
    + "next last week month year due mon tue wed thu fri sat sun monday tuesday "
    + "wednesday thursday friday saturday sunday").split(/\s+/);
var STOP = {};
for (var s = 0; s < STOPWORDS.length; s++) STOP[STOPWORDS[s]] = true;

function fromTitle(text) {
    // QML's JS engine predates \p{L} property escapes, so spell out the letter
    // ranges instead: Latin, combining marks, Greek/Cyrillic, CJK and Hangul.
    var words = String(text || "").toLowerCase().match(/[a-z0-9\u00c0-\u024f\u0250-\u036f\u0370-\u1fff\u2c00-\ud7ff\uf900-\ufdcf\ufdf0-\uffef]+/gi) || [];
    var seen = {}, tags = [];
    for (var i = 0; i < words.length; i++) {
        var word = words[i];
        if (word.length < 2 || /^\d+$/.test(word) || STOP[word] || seen[word]) continue;
        seen[word] = true;
        tags.push(word.slice(0, 32));
        if (tags.length >= 8) break;
    }
    return tags;
}
// Renaming re-derives tags from the new title but keeps any curated tags the
// user or the LLM pass already added. Capped to match setTaskTags.
function mergeTags(existing, title) {
    var seen = {}, next = [];
    var all = (Array.isArray(existing) ? existing : []).concat(fromTitle(title));
    for (var i = 0; i < all.length; i++) {
        var tag = String(all[i] || "").trim().toLowerCase().slice(0, 32);
        if (!tag || seen[tag]) continue;
        seen[tag] = true;
        next.push(tag);
        if (next.length >= 12) break;
    }
    return next;
}
