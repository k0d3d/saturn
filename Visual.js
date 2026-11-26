// Pure helpers for Saturn's card language. No Qt or persistence here so the
// same rules can be unit tested in Node and reused by the shell.
function clamp(value, low, high) {
    var number = Number(value) || 0;
    return Math.max(low, Math.min(high, number));
}

// Stable slots, independent of counts. Narrow screens keep the same grid but
// let each card scroll internally instead of spilling past the viewport.
function grid(width, height) {
    var gap = 28, w = Math.max(320, width), h = Math.max(640, height);
    function box(x, y, width, height) { return {x:x, y:y, width:width, height:height}; }
    if (w < 1400) {
        var half = (w - gap) / 2;
        var r1 = Math.floor((h - 2 * gap) * 0.44);
        var r2 = Math.floor((h - 2 * gap) * 0.28);
        var r3 = h - r1 - r2 - 2 * gap;
        return {height:h, cards:{
            tasks:box(0, 0, half, r1), notes:box(half + gap, 0, half, r1),
            focus:box(0, r1 + gap, half, r2), events:box(half + gap, r1 + gap, half, r2),
            mail:box(0, r1 + r2 + 2 * gap, w, r3)
        }};
    }
    var left = Math.floor((w - 2 * gap) * 0.35);
    var middle = Math.floor((w - 2 * gap) * 0.35);
    var right = w - left - middle - 2 * gap;
    var split = h - 330 - gap;
    var sideSplit = Math.floor((h - gap) * 0.46);
    return {height:h, cards:{
        tasks:box(0, 0, left, h),
        notes:box(left + gap, 0, middle, split),
        focus:box(left + gap, split + gap, middle, 330),
        events:box(left + middle + 2 * gap, 0, right, sideSplit),
        mail:box(left + middle + 2 * gap, sideSplit + gap, right, h - sideSplit - gap)
    }};
}

// Volume bands keep decoration bounded: never one stack layer per item.
function volume(count) {
    var total = clamp(count, 0, 100000);
    if (total <= 0) return 0;
    if (total < 3) return 1;
    if (total < 8) return 2;
    return 3;
}

// Attention is about urgency, not volume. A single overdue task outranks a
// full inbox, so the leading edge has one clear meaning.
function attention(tasks, today, unread) {
    var rows = Array.isArray(tasks) ? tasks : [];
    var overdue = 0;
    var dueToday = 0;
    for (var i = 0; i < rows.length; i++) {
        var task = rows[i] || {};
        if (task.done || task.archived || !task.due) continue;
        if (task.due < today) overdue++;
        else if (task.due === today) dueToday++;
    }
    var mail = clamp(unread, 0, 100000);
    if (overdue > 0) return {level: 2, count: overdue, reason: "overdue"};
    if (mail > 0) return {level: 1, count: mail, reason: "unread"};
    if (dueToday > 0) return {level: 1, count: dueToday, reason: "today"};
    return {level: 0, count: 0, reason: ""};
}

// Library notes dated to a day, oldest pinned first, then most recently
// edited. Daily notes are excluded: the daily note is the hub itself.
function forDay(state, day) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(day || ""))) return [];
    var library = state && Array.isArray(state.notesV2) ? state.notesV2 : [];
    var rows = [];
    for (var i = 0; i < library.length; i++) {
        var note = library[i] || {};
        if (note.archived || note.date !== day) continue;
        rows.push({id: note.id, title: note.title || "Untitled note",
                   body: note.body || "", tags: note.tags || [],
                   pinned: !!note.pinned, updatedAt: Number(note.updatedAt) || 0});
    }
    rows.sort(function(a, b) {
        if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
        return b.updatedAt - a.updatedAt;
    });
    return rows;
}
