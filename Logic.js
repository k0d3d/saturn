function dayKey(ms) {
    var d = new Date(ms);
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
function calendarOverlay(events, feed, source) {
    var remoteIds = {};
    (feed || []).forEach(function(event) { if (event.id) remoteIds[event.id] = true; });
    return (events || []).filter(function(event) {
        return !event.archived && !(source === "google" && event.source === "google" && remoteIds[event.externalId]);
    });
}
function defaultSettings() {
    return {llm: {enabled: true, model: "opencode/deepseek-v4.1-flash-free",
                  hours: [9, 18], batch: 20, timeout: 120, prompt: ""}};
}
function fresh() {
    return {version: 2, tasks: [], notes: {}, notesV2: [], events: [], activity: {},
            focus: {title: "Open focus", duration: 1500, elapsed: 0, running: false},
            sync: {providers: {}, conflicts: [], tombstones: []}, insights: {},
            settings: defaultSettings()};
}
function finite(value) {
    return typeof value === "number" && isFinite(value) && value >= 0;
}
function dateKey(value) {
    return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}
function stringList(value, label) {
    if (!Array.isArray(value) || value.some(function(v) { return typeof v !== "string"; })) throw new Error("Unrecognized " + label);
    return value;
}
function migrate(s) {
    if (!s || typeof s !== "object" || Array.isArray(s)) throw new Error("Unrecognized workspace data");
    var version = s.version === undefined ? 1 : s.version;
    if (version !== 1 && version !== 2) throw new Error("Unrecognized workspace version: " + version);
    var tasks = s.tasks === undefined ? [] : s.tasks;
    if (!Array.isArray(tasks)) throw new Error("Unrecognized tasks");

    var out = Object.assign({}, s);
    out.version = 2;
    if (out.settings === undefined) out.settings = defaultSettings();
    out.tasks = tasks.map(function(raw) {
        if (!raw || typeof raw !== "object" || typeof raw.id !== "string" || typeof raw.title !== "string") throw new Error("Unrecognized task");
        var task = Object.assign({}, raw);
        task.due = dateKey(task.due);
        if (task.createdAt === undefined) task.createdAt = finite(task.completedAt) ? task.completedAt : 0;
        if (task.updatedAt === undefined) task.updatedAt = finite(task.completedAt) ? task.completedAt : 0;
        if (task.archived === undefined) task.archived = false;
        if (task.archivedAt === undefined) task.archivedAt = 0;
        if (task.body === undefined) task.body = "";
        if (task.tags === undefined) task.tags = [];
        if (task.source === undefined) task.source = "local";
        if (task.externalId === undefined) task.externalId = null;
        if (typeof task.archived !== "boolean" || !finite(task.archivedAt)) throw new Error("Unrecognized task archive state");
        stringList(task.tags, "task tags");
        return task;
    });

    var notes = s.notes === undefined ? {} : s.notes;
    if (typeof notes !== "object" || Array.isArray(notes) || Object.keys(notes).some(function(k) { return typeof notes[k] !== "string"; })) throw new Error("Unrecognized daily notes");
    out.notes = notes;

    var library = s.notesV2 === undefined ? [] : s.notesV2;
    if (!Array.isArray(library)) throw new Error("Unrecognized notes");
    out.notesV2 = library.map(function(raw) {
        if (!raw || typeof raw !== "object" || typeof raw.id !== "string" || typeof raw.title !== "string" || typeof raw.body !== "string") throw new Error("Unrecognized note");
        var note = Object.assign({}, raw);
        note.date = dateKey(note.date);
        if (note.tags === undefined) note.tags = [];
        if (note.createdAt === undefined) note.createdAt = 0;
        if (note.updatedAt === undefined) note.updatedAt = 0;
        if (note.archived === undefined) note.archived = false;
        if (note.pinned === undefined) note.pinned = false;
        stringList(note.tags, "note tags");
        if (!finite(note.createdAt) || !finite(note.updatedAt) || typeof note.archived !== "boolean" || typeof note.pinned !== "boolean") throw new Error("Unrecognized note metadata");
        return note;
    });

    var events = s.events === undefined ? [] : s.events;
    if (!Array.isArray(events)) throw new Error("Unrecognized events");
    out.events = events.map(function(raw) {
        if (!raw || typeof raw !== "object" || typeof raw.id !== "string" || typeof raw.title !== "string") throw new Error("Unrecognized event");
        var event = Object.assign({}, raw);
        if (event.createdAt === undefined) event.createdAt = 0;
        if (event.updatedAt === undefined) event.updatedAt = 0;
        if (event.archived === undefined) event.archived = false;
        if (!finite(event.createdAt) || !finite(event.updatedAt) || typeof event.archived !== "boolean") throw new Error("Unrecognized event metadata");
        return event;
    });

    var activity = s.activity === undefined ? {} : s.activity;
    if (typeof activity !== "object" || Array.isArray(activity) || Object.keys(activity).some(function(k) { return !finite(activity[k]); })) throw new Error("Unrecognized focus activity");
    out.activity = activity;

    var focus = s.focus === undefined ? {} : s.focus;
    if (typeof focus !== "object" || Array.isArray(focus) || typeof focus.title !== "string") throw new Error("Unrecognized focus state");
    var duration = focus.duration === undefined ? 0 : focus.duration;
    var elapsed = focus.elapsed === undefined ? 0 : focus.elapsed;
    if (!finite(duration) || !finite(elapsed)) throw new Error("Unrecognized focus state");
    out.focus = Object.assign({}, focus, {running: false});

    ["mailSource", "calendarSource"].forEach(function(key) {
        if (s[key] !== undefined && typeof s[key] !== "string") throw new Error("Unrecognized " + key);
    });
    if (s.mailSource !== undefined && ["hey", "gmail", "outlook", "imap", "off"].indexOf(s.mailSource) < 0) throw new Error("Unrecognized mail source");
    if (s.calendarSource !== undefined && ["omacal", "google", "off"].indexOf(s.calendarSource) < 0) throw new Error("Unrecognized calendar source");

    var sync = s.sync === undefined ? {} : s.sync;
    if (typeof sync !== "object" || Array.isArray(sync)) throw new Error("Unrecognized sync metadata");
    out.sync = Object.assign({}, sync, {
        providers: sync.providers === undefined ? {} : sync.providers,
        conflicts: sync.conflicts === undefined ? [] : sync.conflicts,
        tombstones: sync.tombstones === undefined ? [] : sync.tombstones
    });
    if (typeof out.sync.providers !== "object" || Array.isArray(out.sync.providers) || !Array.isArray(out.sync.conflicts) || !Array.isArray(out.sync.tombstones)
        || (out.sync.audit !== undefined && !Array.isArray(out.sync.audit))) throw new Error("Unrecognized sync metadata");

    var insights = s.insights === undefined ? {} : s.insights;
    if (typeof insights !== "object" || Array.isArray(insights)) throw new Error("Unrecognized insights");
    out.insights = insights;
    return out;
}
function parse(raw) {
    if (!raw.trim()) return fresh();
    return migrate(JSON.parse(raw));
}
function serialize(state) {
    return JSON.stringify(state, null, 2) + "\n";
}
// A file event caused by our own atomic write is not an external edit.
function shouldAdopt(incoming, lastPersisted, ready, error) {
    return !(ready && !error && incoming === lastPersisted);
}
function needsWrite(state, lastPersisted) {
    return serialize(state) !== lastPersisted;
}
function tasksInView(tasks, view, today) {
    var all = Array.isArray(tasks) ? tasks : [];
    // Qt's JS sort is not stable, so equal keys (every undated task) would come
    // back in an arbitrary order. The workspace position is the tiebreaker.
    var position = {};
    all.forEach((t, i) => position[t.id] = i);
    var stable = (a, b) => (position[a.id] || 0) - (position[b.id] || 0);
    var byDue = (a, b) => (a.due || "9999").localeCompare(b.due || "9999") || stable(a, b);
    var newest = key => (a, b) => (b[key] || 0) - (a[key] || 0) || stable(a, b);
    if (view === "Completed") return all.filter(t => t.done && !t.archived).sort(newest("completedAt"));
    if (view === "Archive") return all.filter(t => t.archived).sort(newest("archivedAt"));
    if (view === "Upcoming") return all.filter(t => !t.archived && !t.done && t.due && t.due > today).sort(byDue);
    if (view === "Today") return all.filter(t => !t.archived && !t.done && (!t.due || t.due <= today)).sort(byDue);
    return all.filter(t => !t.archived && !t.done);
}
function withTag(tasks, tag) {
    if (!tag) return Array.isArray(tasks) ? tasks : [];
    return (tasks || []).filter(t => (t.tags || []).indexOf(tag) >= 0);
}
function tagCloud(tasks) {
    var counts = {}, tags = [];
    (tasks || []).forEach(function(task) {
        if (task.archived) return;
        (task.tags || []).forEach(function(tag) {
            if (!counts[tag]) { counts[tag] = 0; tags.push(tag); }
            counts[tag]++;
        });
    });
    return tags.map(function(tag) { return { tag: tag, count: counts[tag] }; })
        .sort(function(a, b) { return b.count - a.count || a.tag.localeCompare(b.tag); });
}
function dayLabel(key, today) {
    if (!key || key === "0") return "Older";
    if (key === today) return "Today";
    var d = new Date(key + "T12:00:00Z");
    var y = new Date(today + "T12:00:00Z");
    y.setUTCDate(y.getUTCDate() - 1);
    if (key === y.toISOString().slice(0, 10)) return "Yesterday";
    var sameYear = key.slice(0, 4) === today.slice(0, 4);
    return d.toLocaleDateString(undefined, sameYear
        ? { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }
        : { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}
function taskGroups(rows, today) {
    var seen = {}, groups = [];
    (rows || []).forEach(function(task) {
        var key = task.createdAt ? dayKey(task.createdAt) : "0";
        if (!seen[key]) {
            seen[key] = { key: key, label: dayLabel(key, today), tasks: [] };
            groups.push(seen[key]);
        }
        seen[key].tasks.push(task);
    });
    // Newest group first; tasks with no created date close the list.
    groups.sort(function(a, b) {
        if (a.key === "0") return 1;
        if (b.key === "0") return -1;
        return b.key.localeCompare(a.key);
    });
    return groups;
}
function advance(s, delta, now) {
    if (!s.focus.running) return "idle";
    // Suspend or a stalled desktop must not count as active work.
    if (delta <= 0 || delta > 3) { s.focus.running = false; return "paused"; }
    var amount = s.focus.duration > 0 ? Math.min(delta, Math.max(0, s.focus.duration - s.focus.elapsed)) : delta;
    s.focus.elapsed += amount;
    var key = dayKey(now);
    s.activity[key] = (s.activity[key] || 0) + amount;
    if (s.focus.duration > 0 && s.focus.elapsed >= s.focus.duration) {
        s.focus.running = false;
        return "finished";
    }
    return "running";
}
function clock(seconds) {
    var n = Math.max(0, Math.ceil(seconds));
    var h = Math.floor(n / 3600);
    return (h ? h + ":" : "") + String(Math.floor(n / 60) % (h ? 60 : 100000)).padStart(2, "0") + ":" + String(n % 60).padStart(2, "0");
}
function calendarDays(feed) {
    var panel = feed.panel || {};
    var base = panel.date || dayKey(Date.now());
    var days = panel.agenda_days || [{date_label: panel.date_label || base, events: panel.events || feed.events || []}];
    return days.map(function(day, index) {
        // Increment date strings in UTC to avoid DST or machine/calendar zone differences.
        var d = new Date(base + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + index);
        return {date: d.toISOString().slice(0, 10), label: day.date_label,
                events: (day.events || []).filter(e => typeof e.start_ms === "number" && typeof e.end_ms === "number").slice().sort((a,b) => a.start_ms - b.start_ms)};
    });
}
