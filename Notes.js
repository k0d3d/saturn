// Pure helpers for the local notes library. Service.qml owns all persistence.
function normaliseTags(value) {
    var raw = Array.isArray(value) ? value : String(value || "").split(/[,;#\s]+/);
    var seen = {};
    var result = [];
    for (var i = 0; i < raw.length && result.length < 12; i++) {
        var tag = String(raw[i] || "").trim().replace(/^#/, "").slice(0, 32).toLowerCase();
        if (tag && !seen[tag]) { seen[tag] = true; result.push(tag); }
    }
    return result;
}
function tagsText(tags) {
    return (Array.isArray(tags) ? tags : []).join(", ");
}
function newId(now) {
    return now.toString(36) + Math.random().toString(36).slice(2, 8);
}
function make(data, now) {
    return {
        id: newId(now),
        title: String(data && data.title || "Untitled note").trim().slice(0, 200) || "Untitled note",
        body: String(data && data.body || "").slice(0, 20000),
        tags: normaliseTags(data && data.tags),
        date: /^\d{4}-\d{2}-\d{2}$/.test(String(data && data.date || "")) ? data.date : null,
        createdAt: now,
        updatedAt: now,
        archived: false,
        pinned: false
    };
}
function update(note, data, now) {
    var out = Object.assign({}, note);
    if (data.title !== undefined) out.title = String(data.title).trim().slice(0, 200) || note.title;
    if (data.body !== undefined) out.body = String(data.body).slice(0, 20000);
    if (data.tags !== undefined) out.tags = normaliseTags(data.tags);
    if (data.date !== undefined) out.date = /^\d{4}-\d{2}-\d{2}$/.test(String(data.date || "")) ? data.date : null;
    out.updatedAt = now;
    return out;
}
function dailyId(date) { return "daily:" + date; }
function isDaily(id) { return typeof id === "string" && id.indexOf("daily:") === 0; }
function excerpt(body, length) {
    var text = String(body || "").replace(/\s+/g, " ").trim();
    return text.length > (length || 90) ? text.slice(0, length || 90) + "…" : text;
}
function plain(body) {
    return String(body || "")
        .replace(/\[\[([^\[\]]+)\]\]/g, "$1")
        .replace(/^#+\s*/gm, "")
        .replace(/\s+/g, " ")
        .trim();
}
function boardDate(date, today) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(date || ""))) return "Undated";
    var noteDay = new Date(date + "T12:00:00Z");
    var currentDay = new Date(String(today || "") + "T12:00:00Z");
    if (isNaN(noteDay.getTime()) || noteDay.toISOString().slice(0, 10) !== date ||
        isNaN(currentDay.getTime())) return "Undated";
    var days = Math.round((currentDay.getTime() - noteDay.getTime()) / 86400000);
    if (days === 0) return "Today";
    if (days === 1) return "Yesterday";
    if (days >= 2 && days <= 6) return days + " days ago";
    if (days === -1) return "Tomorrow";
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return noteDay.getUTCDate() + " " + months[noteDay.getUTCMonth()] +
        (noteDay.getUTCFullYear() === currentDay.getUTCFullYear() ? "" : " " + noteDay.getUTCFullYear());
}
function readingLines(body) {
    var input = String(body || "").trim() || "No text yet.";
    return input.split("\n").map(function(line) {
        var heading = /^#{1,6}\s+/.test(line);
        if (heading) line = line.replace(/^#{1,6}\s+/, "");
        var parts = [], cursor = 0, match, pattern = /\[\[([^\[\]]{1,200})\]\]/g;
        while ((match = pattern.exec(line)) !== null) {
            if (match.index > cursor) parts.push({text: line.slice(cursor, match.index)});
            parts.push({reference: match[1]});
            cursor = pattern.lastIndex;
        }
        if (cursor < line.length) parts.push({text: line.slice(cursor)});
        return {heading: heading, parts: parts};
    });
}
function matches(note, query) {
    if (!query) return true;
    var terms = String(query).toLowerCase().split(/\s+/).filter(Boolean);
    var haystack = [note.title, note.body, note.date || "", tagsText(note.tags)].join(" ").toLowerCase();
    return terms.every(function(term) { return haystack.indexOf(term) >= 0; });
}
// Library notes plus day-keyed daily notes, with pinned items first.
function search(state, query, limit, today) {
    var max = Math.min(Math.max(Number(limit) || 80, 1), 100);
    var results = [];
    var library = state && Array.isArray(state.notesV2) ? state.notesV2 : [];
    for (var i = 0; i < library.length; i++) {
        var note = library[i];
        if (!matches(note, query)) continue;
        results.push({id: note.id, title: note.title, body: note.body, tags: note.tags || [],
                      date: note.date || null, archived: !!note.archived, pinned: !!note.pinned,
                      updatedAt: note.updatedAt || 0, source: "library"});
    }
    var days = state && state.notes ? state.notes : {};
    for (var date in days) {
        if (!Object.prototype.hasOwnProperty.call(days, date)) continue;
        var daily = {title: "Daily note · " + boardDate(date, today), body: days[date], date: date, tags: [],
                     archived: false, pinned: false, updatedAt: 0};
        if (!matches(daily, query)) continue;
        results.push({id: dailyId(date), title: daily.title, body: excerpt(daily.body, 200),
                      tags: [], date: date, archived: false, pinned: false,
                      updatedAt: 0, source: "daily"});
    }
    function key(item) {
        return item.date ? item.date : String(Math.max(0, Number(item.updatedAt) || 0)).padStart(16, "0");
    }
    results.sort(function(a, b) {
        if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
        return key(b).localeCompare(key(a));
    });
    return results.slice(0, max);
}
