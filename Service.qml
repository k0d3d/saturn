pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Logic.js" as Logic
import "Dates.js" as Dates
import "Notes.js" as Notes
import "Visual.js" as Visual

Item {
    id: root
    property var shell
    property var manifest
    property string omarchyPath
    property var pluginRegistry
    property var workspace: Logic.fresh()
    property int revision: 0
    property int taskRevision: 0
    property bool ready: false
    property bool storagePrepared: false
    property string error: ""
    property string notice: ""
    property string notesQuery: ""
    // UI-local navigation target. It never touches workspace.json.
    property string notesSelection: ""
    // Canonical serialization the shell last wrote, used to ignore its own file events.
    property string lastPersisted: ""
    property double now: Date.now()
    property double previousTick: Date.now()
    property string today: Logic.dayKey(now)
    property string noteDay: today
    property var agenda: []
    property var agendaDays: []
    property string calendarToday: today
    property var calendarClocks: ({})
    property string calendarTimezone: ""
    property double agendaUpdated: 0
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/saturn"
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    property bool mailEnabled: true
    readonly property alias hey: mailController
    readonly property string mailSource: workspace.mailSource || "hey"
    readonly property string calendarSource: workspace.calendarSource || "omacal"
    readonly property string mailName: ({hey:"HEY",gmail:"Gmail",outlook:"Outlook",imap:"IMAP",off:"Mail"})[mailSource]
    readonly property string calendarName: calendarSource === "google" ? "Google Calendar" : calendarSource === "caldav" ? "CalDAV" : calendarSource === "off" ? "Calendar off" : "OmaCal"
    readonly property var mail: mailSource === "gmail" ? gmailController : mailSource === "outlook" ? outlookController : mailSource === "imap" ? imapController : mailController
    readonly property var newMail: mailSource !== "off" && mail ? mail.notifications.filter(m => m.unread) : []
    readonly property alias imap: imapController
    readonly property alias gmail: gmailController
    readonly property alias outlook: outlookController
    readonly property alias googleCalendar: googleController
    readonly property alias caldavCalendar: caldavController
    ProviderStore { id: caldavController; provider: "caldav"; active: root.ready && root.calendarSource === "caldav" }
    HeyStore { id: mailController; active: root.mailEnabled && root.mailSource === "hey" }
    ProviderStore { id: gmailController; provider: "gmail"; active: root.ready && root.mailEnabled && root.mailSource === "gmail" }
    ProviderStore { id: outlookController; provider: "outlook"; active: root.ready && root.mailEnabled && root.mailSource === "outlook" }
    ProviderStore { id: imapController; provider: "imap"; active: root.ready && root.mailEnabled && root.mailSource === "imap" }
    ProviderStore { id: googleController; provider: "google-calendar"; active: root.ready && root.calendarSource === "google"; onFeedChanged: if(root.calendarSource === "google") { root.applyGoogleCalendar(); root.applyLocalEvents(); } }
    function setMailSource(source) {
        if (!ready || ["hey","gmail","outlook","imap","off"].indexOf(source)<0) return;
        workspace=Object.assign({},workspace,{mailSource:source}); changed();
    }
    function setCalendarSource(source) {
        if (!ready || ["omacal","google","caldav","off"].indexOf(source)<0) return;
        workspace=Object.assign({},workspace,{calendarSource:source}); changed();
    }
    onCalendarSourceChanged: {
        agenda=[]; agendaDays=[]; calendarClocks=({}); calendarTimezone=""; calendarToday=today;
        if(calendarSource === "omacal") feed.reload();
        else if(calendarSource === "google") { applyGoogleCalendar(); googleController.refreshIfStale(); }
        else if(calendarSource === "caldav") { agenda=[]; agendaDays=[]; root.calendarSync("sync"); }
    }
    function applyGoogleCalendar() {
        agenda=googleController.events; agendaDays=googleController.days; calendarClocks=googleController.clocks;
        calendarTimezone=googleController.timezone; calendarToday=googleController.today || today; agendaUpdated=Date.now();
    }
    function applyLocalEvents() {
        revision;
        agenda = agenda.filter(e => !e.localId);
        var rows = Logic.calendarOverlay(workspace.events, googleController.events, calendarSource);
        var days = agendaDays.map(d => Object.assign({}, d, {events: d.events.filter(e => !e.localId)}));
        rows.forEach(function(event) {
            var start = new Date(typeof event.start === "number" ? event.start : Date.parse(event.start));
            var end = new Date(typeof event.end === "number" ? event.end : (start.getTime() + 3600000));
            if (isNaN(start.getTime())) return;
            var key = Logic.dayKey(start.getTime());
            var row = {title: event.title, start_ms: start.getTime(), end_ms: end.getTime(),
                       all_day: !!event.all_day, calendar: event.source || "Local",
                       localId: event.id, url: ""};
            agenda.push(row);
            var day = days.find(d => d.date === key);
            if (!day) { day = {date: key, label: Qt.formatDate(start, "ddd d MMM"), events: []}; days.push(day); }
            day.events.push(row);
        });
        days.sort((a,b) => a.date.localeCompare(b.date));
        days.forEach(d => d.events.sort((a,b) => a.start_ms - b.start_ms));
        agendaDays = days;
        agendaUpdated = Date.now();
    }
    function addEvent(title, start, end) {
        if (!ready || error || !String(title || "").trim()) return "";
        var stamp = Date.now();
        var id = stamp.toString(36) + Math.random().toString(36).slice(2, 8);
        var when = Date.parse(start);
        if (isNaN(when)) when = stamp;
        workspace.events.unshift({id: id, title: String(title).trim().slice(0, 256),
            start: when, end: isNaN(Date.parse(end)) ? when + 3600000 : Date.parse(end),
            all_day: false, calendar: "Local", source: "local", externalId: null,
            archived: false, createdAt: stamp, updatedAt: stamp});
        changed(); applyLocalEvents();
        if (calendarSource === "google" || calendarSource === "caldav") calendarSync("sync");
        return id;
    }
    function archiveEvent(id) {
        var event = workspace.events.find(e => e.id === id);
        if (!event || !ready || error) return;
        event.archived = true; event.updatedAt = Date.now();
        changed(); applyLocalEvents();
        if (calendarSource === "google" || calendarSource === "caldav") calendarSync("sync");
    }
    function applyCalendarFeed() { applyLocalEvents(); }
    function openMail(target) {
        if (mailSource === "imap") {
            if (/^https:\/\/[^\s/]+(?:[/?#]|$)/i.test(imapController.webmailUrl)) Quickshell.execDetached(["xdg-open",imapController.webmailUrl]);
            return;
        }
        var homes={hey:"https://app.hey.com",gmail:"https://mail.google.com/mail/",outlook:"https://outlook.office.com/mail/"};
        var allowed={hey:/^https:\/\/app\.hey\.com(?:[/?#]|$)/i,gmail:/^https:\/\/mail\.google\.com(?:[/?#]|$)/i,outlook:/^https:\/\/outlook\.(?:office\.com|office365\.com|live\.com)(?:[/?#]|$)/i};
        if (!homes[mailSource]) return;
        var destination=allowed[mailSource].test(target || "") ? target : homes[mailSource];
        Quickshell.execDetached(mailSource === "hey" ? ["omarchy","launch","webapp",destination] : ["xdg-open",destination]);
    }
    function showPulse(view, target) {
        if(view === "close") { eachWindow(w => { w.commandOpen=false; w.dashboardOpen=false; w.close(); }); return; }
        notesSelection = target || "";
        eachWindow(w => {
            w.workspacePanel.connectionsOpen=false; w.workspacePanel.insights=false; w.workspacePanel.notesOpen=false;
            if(view === "notes") w.workspacePanel.notesOpen=true;
            else if(view === "connections") w.workspacePanel.connectionsOpen=true;
            else if(view === "insights") w.workspacePanel.insights=true;
            w.commandOpen=false; w.open();
        });
    }
    readonly property var tasks: { taskRevision; return workspace.tasks.map(t => Object.assign({}, t)); }
    readonly property var focusState: { revision; return Object.assign({}, workspace.focus); }
    readonly property string note: { revision; return workspace.notes[noteDay] || ""; }
    readonly property int remainingTasks: tasks.filter(t => !t.done && !t.archived).length
    readonly property string timerText: { revision; return Logic.clock(workspace.focus.duration ? workspace.focus.duration - workspace.focus.elapsed : workspace.focus.elapsed); }
    readonly property int todayMinutes: { revision; return Math.floor((workspace.activity[today] || 0) / 60); }
    readonly property int todayCompleted: { revision; return workspace.tasks.filter(t => t.done && Logic.dayKey(t.completedAt) === today).length; }
    readonly property var week: {
        revision;
        var rows = [];
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now); d.setDate(d.getDate() - i);
            var key = Logic.dayKey(d.getTime());
            rows.push({label: Qt.formatDate(d, "ddd"), minutes: Math.floor((workspace.activity[key] || 0) / 60)});
        }
        return rows;
    }
    function changed(save, tasksChanged) { revision++; if (tasksChanged) taskRevision++; if (save !== false && ready) saveTimer.restart(); }
    function recordAgentAction(command) {
        if (!ready) return;
        if (!workspace.sync || typeof workspace.sync !== "object") workspace.sync = {};
        if (!Array.isArray(workspace.sync.audit)) workspace.sync.audit = [];
        workspace.sync.audit.push({at: Date.now(), command: String(command || "").slice(0, 60)});
        workspace.sync.audit = workspace.sync.audit.slice(-200);
        changed(false);
    }
    function flush() {
        if (!ready || error || !Logic.needsWrite(workspace, lastPersisted)) return;
        var payload = Logic.serialize(workspace);
        lastPersisted = payload;
        storage.setText(payload);
    }
    signal taskAdded(string title)
    function addTask(title, dueText) {
        var parsed = Dates.parseDue(title, today);
        var due = Dates.validDay(dueText) ? dueText : parsed.due;
        if (!ready || error || !parsed.title) return;
        var stamp = Date.now();
        workspace.tasks.unshift({
            id: stamp.toString(36) + Math.random().toString(36).slice(2, 8),
            title: parsed.title,
            done: false,
            completedAt: 0,
            due: due,
            createdAt: stamp,
            updatedAt: stamp,
            archived: false,
            archivedAt: 0,
            body: "",
            tags: [],
            source: "local",
            externalId: null
        });
        changed(true, true);
        taskAdded(parsed.title);
    }
    function findTask(id) { return workspace.tasks.find(t => t.id === id); }
    function setTaskDue(id, due) {
        var t = findTask(id);
        if (!t || !ready || error) return;
        t.due = Dates.validDay(due) ? due : null;
        t.updatedAt = Date.now();
        changed(true, true);
    }
    function renameTask(id, title) {
        var t = findTask(id);
        var text = String(title || "").trim().slice(0, 500);
        if (!t || !ready || error || !text || text === t.title) return false;
        t.title = text;
        t.updatedAt = Date.now();
        changed(true, true);
        return true;
    }
    // Tags are lowercased and de-duplicated so the graph gets one node per theme
    // instead of near-duplicates that read as separate clusters.
    function setTaskTags(id, raw) {
        var t = findTask(id);
        if (!t || !ready || error) return false;
        var seen = {}, next = [];
        var parts = String(raw || "").toLowerCase().split(/[,;#\s]+/);
        for (var i = 0; i < parts.length; i++) {
            var tag = parts[i].slice(0, 32);
            if (!tag || seen[tag]) continue;
            seen[tag] = true;
            next.push(tag);
            if (next.length >= 12) break;
        }
        t.tags = next;
        t.updatedAt = Date.now();
        changed(true, true);
        return true;
    }
    function archiveTask(id) {
        var t = findTask(id);
        if (!t || !ready || error || t.archived) return;
        t.archived = true; t.archivedAt = Date.now(); t.updatedAt = t.archivedAt;
        changed(true, true);
        notice = "Task archived · undo from Archive.";
    }
    function restoreTask(id) {
        var t = findTask(id);
        if (!t || !ready || error || !t.archived) return;
        t.archived = false; t.archivedAt = 0; t.updatedAt = Date.now();
        changed(true, true);
        notice = "Task restored.";
    }
    function dismissWorkspace() {
        eachWindow(w => { w.commandOpen = false; w.dashboardOpen = false; w.close(); });
    }
    function openCalendar(date) {
        if (calendarSource === "off" || calendarSource === "caldav") return;
        var day = /^\d{4}-\d{2}-\d{2}$/.test(date || "") ? date : calendarToday;
        if (calendarSource === "google") {
            Quickshell.execDetached(["xdg-open","https://calendar.google.com/calendar/u/0/r/day/" + day.replace(/-/g,"/") + "?authuser=" + encodeURIComponent(googleController.accountEmail)]);
            dismissWorkspace(); return;
        }
        // Raise an existing calendar even when it lives on another workspace.
        Quickshell.execDetached(["sh", "-c",
            'omacal "$1" >/dev/null 2>&1 & sleep 0.4; '
            + 'hyprctl dispatch \'hl.dsp.focus({ window = "class:omacal" })\'; '
            + 'exec hyprctl dispatch \'hl.dsp.window.bring_to_top({ window = "class:omacal" })\'',
            "saturn-calendar", day]);
        dismissWorkspace();
    }
    function toggleTask(id) {
        var t = findTask(id);
        if (!t || !ready || error) return;
        t.done = !t.done;
        t.completedAt = t.done ? Date.now() : 0;
        t.updatedAt = Date.now();
        changed(true, true);
    }
    function setNote(text) {
        if (!ready || error || text === note) return;
        workspace.notes[noteDay] = text; changed();
    }
    function moveNoteDay(offset) {
        var d = new Date(noteDay + "T12:00:00"); d.setDate(d.getDate() + offset);
        noteDay = Logic.dayKey(d.getTime());
    }
    function findNote(id) { return workspace.notesV2.find(n => n.id === id); }
    function addNote(title, body, tags, date) {
        if (!ready || error) return "";
        var note = Notes.make({title: title, body: body, tags: tags, date: date}, Date.now());
        workspace.notesV2.unshift(note);
        changed();
        return note.id;
    }
    function updateNote(id, title, body, tags, date) {
        var index = workspace.notesV2.findIndex(n => n.id === id);
        if (index < 0 || !ready || error) return false;
        workspace.notesV2[index] = Notes.update(workspace.notesV2[index],
            {title: title, body: body, tags: tags, date: date}, Date.now());
        changed();
        return true;
    }
    function toggleNotePin(id) {
        var note = findNote(id);
        if (!note || !ready || error) return;
        note.pinned = !note.pinned; note.updatedAt = Date.now(); changed();
    }
    function archiveNote(id) {
        var note = findNote(id);
        if (!note || !ready || error || note.archived) return;
        note.archived = true; note.updatedAt = Date.now(); changed();
        notice = "Note archived · undo from the library.";
    }
    function restoreNote(id) {
        var note = findNote(id);
        if (!note || !ready || error || !note.archived) return;
        note.archived = false; note.updatedAt = Date.now(); changed();
        notice = "Note restored.";
    }
    function searchNotes(query, limit) {
        return Notes.search(workspace, query || "", limit || 80);
    }
    // Library notes dated to a day. Used by the daily-note hub; derived, never
    // persisted, so the graph and vault remain the sources of truth.
    function notesForDay(day) { return Visual.forDay(workspace, day); }

    function tasksCommand(command, first, second) {
        var cmd = command || "list";
        if (cmd === "list") return JSON.stringify(root.tasks);
        if (cmd === "add") { root.addTask(first, second); return JSON.stringify({ok: !!first && first.trim().length > 0}); }
        if (cmd === "complete" || cmd === "archive" || cmd === "restore") {
            var task = root.findTask(first);
            if (!task) return JSON.stringify({ok: false, error: "No such task"});
            if (cmd === "complete") root.toggleTask(first);
            else if (cmd === "archive") root.archiveTask(first);
            else root.restoreTask(first);
            return JSON.stringify({ok: true, id: first});
        }
        if (cmd === "due") { root.setTaskDue(first, second); return JSON.stringify({ok: true, id: first, due: second || null}); }
        if (cmd === "tags") {
            var tagged = root.setTaskTags(first, second);
            var item = root.findTask(first);
            return JSON.stringify({ok: tagged, id: first, tags: item ? item.tags : []});
        }
        return JSON.stringify({ok: false, error: "Unknown task command"});
    }
    function notesCommand(command, a, b, c, d) {
        var cmd = command || "list";
        if (cmd === "list") return JSON.stringify(root.workspace.notesV2);
        if (cmd === "search") return JSON.stringify(root.searchNotes(a, b ? Number(b) : 80));
        if (cmd === "add") return JSON.stringify({ok: !!a, id: a ? root.addNote(a, b, c, d) : ""});
        if (cmd === "update") return JSON.stringify({ok: root.updateNote(a, b, c, d)});
        if (cmd === "pin") {
            if (Notes.isDaily(a)) return JSON.stringify({ok: false, error: "Daily notes cannot be pinned"});
            root.toggleNotePin(a); return JSON.stringify({ok: true, id: a});
        }
        if (cmd === "archive" || cmd === "restore") {
            if (Notes.isDaily(a)) return JSON.stringify({ok: false, error: "Daily notes cannot be archived"});
            if (cmd === "archive") root.archiveNote(a); else root.restoreNote(a);
            return JSON.stringify({ok: true, id: a});
        }
        return JSON.stringify({ok: false, error: "Unknown note command"});
    }
    function chooseFocus(title, duration) {
        if (!ready || error) return;
        workspace.focus = {title: title || "Open focus", duration: duration, elapsed: 0, running: false};
        notice = ""; changed();
    }
    function toggleTimer() {
        if (!ready || error) return;
        if (workspace.focus.duration && workspace.focus.elapsed >= workspace.focus.duration) workspace.focus.elapsed = 0;
        workspace.focus.running = !workspace.focus.running;
        previousTick = Date.now(); notice = ""; changed(); flush();
    }
    function addFive() {
        if (!ready || error || !workspace.focus.duration) return;
        workspace.focus.duration += 300; changed();
    }
    Process {
        command: ["python3", Qt.resolvedUrl("initialize.py").toString().replace("file://", "")]
        running: true
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Saturn storage:", text.trim()) }
        onExited: function(code) {
            if (code === 0) root.storagePrepared = true;
            else root.error = "Could not prepare workspace storage. Check " + root.dataDir;
        }
    }
    FileView {
        id: storage
        path: root.storagePrepared ? root.dataDir + "/workspace.json" : ""
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            var incoming = text();
            // Our own atomic write fires a file event; do not re-parse it.
            if (!Logic.shouldAdopt(incoming, root.lastPersisted, root.ready, root.error)) return;
            try {
                var state = Logic.parse(incoming);
                root.workspace = state;
                root.lastPersisted = Logic.serialize(state);
                root.error = "";
                root.ready = true;
                root.changed(false, true);
                root.applyLocalEvents();
            } catch (e) {
                root.error = "Could not read saved workspace. Original file preserved.";
                console.warn("Saturn:", e);
            }
        }
        onLoadFailed: { if (root.storagePrepared) root.error = "Workspace file unavailable. Check " + root.dataDir; }
        onSaveFailed: { root.error = "Saving failed. Keep this workspace open and check disk space."; }
    }
    FileView {
        id: feed
        path: root.stateDir + "/omacal/upcoming.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.calendarSource !== "omacal") return;
            try {
                var f = JSON.parse(text());
                root.agendaDays = Logic.calendarDays(f);
                root.calendarToday = f.panel && f.panel.date ? f.panel.date : root.today;
                root.calendarClocks = f.panel && f.panel.clocks ? f.panel.clocks : ({});
                root.calendarTimezone = f.panel && f.panel.timezone ? f.panel.timezone : "";
                var events = (f.events || []).concat(f.panel && f.panel.events ? f.panel.events : []);
                var seen = {};
                root.agenda = events.filter(function(e) {
                    var key = e.start_ms + ":" + e.end_ms + ":" + e.title;
                    if (seen[key] || typeof e.start_ms !== "number" || typeof e.end_ms !== "number") return false;
                    seen[key] = true; return true;
                });
                root.agendaUpdated = Date.now();
                root.applyLocalEvents();
            } catch (e) { root.agenda = []; root.agendaDays = []; }
        }
        onLoadFailed: { if(root.calendarSource === "omacal") { root.agenda = []; root.agendaDays = []; } }
    }
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
    property int vaultRevision: -1
    property string vaultMode: "sync"
    function vaultSync(mode) {
        if (!ready || error || vaultProcess.running) return;
        root.flush();
        vaultMode = ["push", "pull", "sync", "status"].indexOf(mode) >= 0 ? mode : "sync";
        vaultProcess.running = true;
    }
    Process {
        id: vaultProcess
        command: ["python3", Qt.resolvedUrl("scripts/vault_sync.py").toString().replace("file://", ""), root.vaultMode]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text);
                    if (result.ok && (result.pushed || result.pulled)) root.notice = "Markdown vault synced.";
                    else if (!result.ok) root.notice = "Vault sync: " + (result.error || "failed");
                } catch (e) {}
            }
        }
        onExited: function(code) { if (code === 0) storage.reload(); }
    }
    Timer {
        interval: 5000; repeat: true; running: root.ready
        onTriggered: {
            if (root.revision !== root.vaultRevision) {
                root.vaultRevision = root.revision;
                root.vaultSync("push");
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: root.ready; onTriggered: root.vaultSync("sync") }
    property string calendarMode: "sync"
    function calendarSync(mode) {
        if (!ready || error || calendarProcess.running) return;
        root.flush();
        calendarMode = (mode === "sync" || mode === "status") ? mode : "sync";
        calendarProcess.running = true;
    }
    Process {
        id: calendarProcess
        command: ["python3", Qt.resolvedUrl("scripts/calendar_sync.py").toString().replace("file://", ""), root.calendarMode]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text);
                    if (!result.ok) root.notice = "Calendar sync: " + (result.error || "failed");
                } catch (e) {}
            }
        }
        onExited: function(code) { if (code === 0) storage.reload(); }
    }
    Timer {
        interval: 60000; repeat: true; running: root.ready && (root.calendarSource === "google" || root.calendarSource === "caldav")
        onTriggered: root.calendarSync("sync")
    }
    Timer {
        interval: 1000; repeat: true; running: root.ready
        onTriggered: {
            var current = Date.now();
            var result = Logic.advance(root.workspace, (current - root.previousTick) / 1000, current);
            root.previousTick = current; root.now = current;
            if (result !== "idle") {
                root.changed(false);
                if (result === "finished") {
                    root.notice = "Session complete. Take a breath.";
                    Quickshell.execDetached(["notify-send", "Saturn · Focus complete", root.workspace.focus.title]);
                } else if (result === "paused") root.notice = "Focus paused while the desktop was away.";
                if (result !== "running" || Math.floor(root.workspace.focus.elapsed) % 5 === 0) root.flush();
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: if(root.calendarSource === "omacal") feed.reload() }
    Instantiator {
        id: windows
        model: Quickshell.screens
        delegate: OwlWindow { required property var modelData; screen: modelData; store: root }
    }
    function eachWindow(action) {
        for (var i = 0; i < windows.count; i++) action(windows.objectAt(i));
    }
    function windowForScreen(name) {
        for (var i = 0; i < windows.count; i++) {
            var panel = windows.objectAt(i);
            if (panel && panel.screen && panel.screen.name === name) return panel;
        }
        return windows.count ? windows.objectAt(0) : null;
    }
    component Control: IpcHandler {
        function barState(screen: string): string {
            var w = root.windowForScreen(screen);
            return JSON.stringify({opened: !!w && (w.dashboardOpen || w.commandOpen), running: root.focusState.running, timer: root.timerText});
        }
        function barAction(screen: string, action: string): void {
            var w = root.windowForScreen(screen);
            if (!w) return;
            var opened = w.dashboardOpen || w.commandOpen;
            if (action === "close" || (action === "click" && opened)) w.close();
            else w.open();
        }
        function open(): void { root.eachWindow(w => w.open()); }
        function close(): void { root.eachWindow(w => { w.commandOpen = false; w.dashboardOpen = false; w.close(); }); }
        function dashboard(): void { if (windows.count > 0) windows.objectAt(0).openDashboard(); }
        function toggle(): void { root.eachWindow(w => { if (w.commandOpen) w.commandOpen = false; else w.openCommand(); }); }
        function command(): void { root.eachWindow(w => w.openCommand()); }
        function tab(name: string): void { root.eachWindow(w => { w.workspacePanel.insights = name === "Insights"; w.open(); }); }
        function tasks(command: string, first: string, second: string): string { return root.tasksCommand(command, first, second); }
        function notes(command: string, a: string, b: string, c: string, d: string): string { return root.notesCommand(command, a, b, c, d); }
        function vaultSync(mode: string): void { root.vaultSync(mode || "sync"); }
        function calendarSync(mode: string): void { root.calendarSync(mode || "sync"); }
        function calendar(command: string, a: string, b: string): string {
            var cmd = command || "list";
            if (cmd === "list") return JSON.stringify(root.workspace.events);
            if (cmd === "add") return JSON.stringify({ok: !!a, id: a ? root.addEvent(a, b, "") : ""});
            if (cmd === "archive") {
                var event = root.workspace.events.find(e => e.id === a);
                if (!event) return JSON.stringify({ok: false, error: "No such event"});
                root.archiveEvent(a); return JSON.stringify({ok: true, id: a});
            }
            return JSON.stringify({ok: false, error: "Unknown calendar command"});
        }
        function notesOpen(): void { root.eachWindow(w => { w.open(); w.workspacePanel.notesOpen = true; }); }
        function notesSearch(query: string): void { root.notesQuery = query || ""; root.eachWindow(w => { w.open(); w.workspacePanel.notesOpen = true; }); }
        function data(command: string, a: string, b: string, c: string, d: string): string {
            var cmd = command || "get";
            if (cmd === "get") return JSON.stringify(root.workspace);
            if (cmd === "sync-status") return JSON.stringify(root.workspace.sync || {});
            if (cmd === "tasks" || cmd === "add-task" || cmd === "complete-task" || cmd === "archive-task" || cmd === "restore-task" || cmd === "set-due" || cmd === "set-tags") {
                var tmap = {"tasks": a || "list", "add-task": "add", "complete-task": "complete",
                            "archive-task": "archive", "restore-task": "restore", "set-due": "due",
                            "set-tags": "tags"};
                var target = tmap[cmd] || "list";
                var taskArgs = cmd === "tasks" ? [b, c] : [a, b];
                var result = root.tasksCommand(target, taskArgs[0] || "", taskArgs[1] || "");
                if (cmd !== "tasks" && cmd !== "list") root.recordAgentAction(cmd);
                return result;
            }
            if (cmd === "notes" || cmd === "add-note" || cmd === "update-note" || cmd === "pin-note" || cmd === "archive-note" || cmd === "restore-note" || cmd === "search") {
                var nmap = {"notes": a || "list", "add-note": "add", "update-note": "update",
                            "pin-note": "pin", "archive-note": "archive", "restore-note": "restore", "search": "search"};
                var ntarget = nmap[cmd] || "list";
                var noteArgs = cmd === "notes" ? [b, c, d] : [a, b, c, d];
                var noteResult = root.notesCommand(ntarget, noteArgs[0] || "", noteArgs[1] || "", noteArgs[2] || "", noteArgs[3] || "");
                if (cmd !== "notes" && cmd !== "search") root.recordAgentAction(cmd);
                return noteResult;
            }
            return JSON.stringify({ok: false, error: "Unknown data command"});
        }
        function status(): string {
            var panels = []; root.eachWindow(w => panels.push({screen: w.screen.name, dashboard: w.dashboardOpen, command: w.commandOpen, timerPopout: w.timerPopout.visible, tab: w.currentTab}));
            return JSON.stringify({ready: root.ready, error: root.error, schema: root.workspace.version, tasks: root.tasks.length, remaining: root.remainingTasks, archived: root.tasks.filter(t => t.archived).length, mailSource: root.mailSource, calendarSource: root.calendarSource, running: root.focusState.running, timer: root.timerText, agendaEvents: root.agenda.length, calendarDays: root.agendaDays.length, windows: panels});
        }
        function connections(): void { root.eachWindow(w => { w.open(); w.workspacePanel.connectionsOpen=true; }); }
        function mailStatus(): string { return JSON.stringify({provider:root.mailSource,connected: root.mail.connected, authenticated: root.mail.authenticated, newForYou: root.newMail.length, busy: root.mail.busy, error: root.mail.lastError}); }
    }
    Control { target: "saturn" }
    Control { target: "omapulse" } // Deprecated aliases for existing shortcuts.
    Control { target: "omaowl" }
    Component.onDestruction: flush()
}
