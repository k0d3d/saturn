// Local task dates. All keys are YYYY-MM-DD in the user's local timezone.
function validDay(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    var d = new Date(value + "T12:00:00Z");
    return !isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}
function addDays(key, amount) {
    var base = validDay(key) ? key : new Date().toISOString().slice(0, 10);
    var d = new Date(base + "T12:00:00Z");
    d.setUTCDate(d.getUTCDate() + amount);
    return d.toISOString().slice(0, 10);
}
function weekday(name, today) {
    var names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
    var wanted = String(name || "").toLowerCase().slice(0, 3);
    var index = names.indexOf(wanted);
    if (index < 0) return null;
    var d = new Date((today || new Date().toISOString().slice(0, 10)) + "T12:00:00Z");
    var delta = (index - d.getUTCDay() + 7) % 7;
    if (delta === 0) delta = 7; // "next Monday" always means a future day.
    return addDays(d.toISOString().slice(0, 10), delta);
}
// Pull a due date out of free text and return the remaining title.
function parseDue(text, today) {
    var value = String(text || "");
    var due = null;
    var match = value.match(/\s+(?:due\s+:?\s*)?(\d{4}-\d{2}-\d{2})\s*$/i);
    if (match && validDay(match[1])) { due = match[1]; value = value.slice(0, match.index); }
    if (!due) {
        match = value.match(/\s+(today|tomorrow|next\s+(?:mon|monday|tue|tuesday|wed|wednesday|thu|thursday|fri|friday|sat|saturday|sun|sunday))\s*$/i);
        if (match) {
            var word = match[1].toLowerCase();
            due = word === "today" ? (today || new Date().toISOString().slice(0, 10))
                : word === "tomorrow" ? addDays(today, 1)
                : weekday(word.replace(/^next\s+/, ""), today);
            if (due) value = value.slice(0, match.index);
        }
    }
    return {title: value.trim().replace(/\s+/g, " ").slice(0, 500), due: due};
}
function dueLabel(due, today) {
    if (!validDay(due)) return "";
    if (due === today) return "Today";
    if (due === addDays(today, 1)) return "Tomorrow";
    if (due < today) return "Overdue · " + due;
    var d = new Date(due + "T12:00:00Z");
    return d.toLocaleDateString(undefined, {month: "short", day: "numeric", timeZone: "UTC"});
}
