pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Logic.js" as Logic
import "Dates.js" as Dates

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
    readonly property string calendarName: calendarSource === "google" ? "Google Calendar" : calendarSource === "off" ? "Calendar off" : "OmaCal"
    readonly property var mail: mailSource === "gmail" ? gmailController : mailSource === "outlook" ? outlookController : mailSource === "imap" ? imapController : mailController
    readonly property var newMail: mailSource !== "off" && mail ? mail.notifications.filter(m => m.unread) : []
    readonly property alias imap: imapController
    readonly property alias gmail: gmailController
    readonly property alias outlook: outlookController
    readonly property alias googleCalendar: googleController
    readonly property alias messages: messageController
    MessageStore { id: messageController; store: root }
    HeyStore { id: mailController; active: root.mailEnabled && root.mailSource === "hey" }
    ProviderStore { id: gmailController; provider: "gmail"; active: root.ready && root.mailEnabled && root.mailSource === "gmail" }
    ProviderStore { id: outlookController; provider: "outlook"; active: root.ready && root.mailEnabled && root.mailSource === "outlook" }
    ProviderStore { id: imapController; provider: "imap"; active: root.ready && root.mailEnabled && root.mailSource === "imap" }
    ProviderStore { id: googleController; provider: "google-calendar"; active: root.ready && root.calendarSource === "google"; onFeedChanged: if(root.calendarSource === "google") root.applyGoogleCalendar() }
    function setMailSource(source) {
        if (!ready || ["hey","gmail","outlook","imap","off"].indexOf(source)<0) return;
        workspace=Object.assign({},workspace,{mailSource:source}); changed();
    }
    function setCalendarSource(source) {
        if (!ready || ["omacal","google","off"].indexOf(source)<0) return;
        workspace=Object.assign({},workspace,{calendarSource:source}); changed();
    }
    onCalendarSourceChanged: {
        agenda=[]; agendaDays=[]; calendarClocks=({}); calendarTimezone=""; calendarToday=today;
        if(calendarSource === "omacal") feed.reload();
        else if(calendarSource === "google") { applyGoogleCalendar(); googleController.refreshIfStale(); }
    }
    function applyGoogleCalendar() {
        agenda=googleController.events; agendaDays=googleController.days; calendarClocks=googleController.clocks;
        calendarTimezone=googleController.timezone; calendarToday=googleController.today || today; agendaUpdated=Date.now();
    }
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
    readonly property alias assistant: assistantController
    Assistant { id: assistantController; store: root }
    readonly property alias voice: voiceController
    VoiceControl { id: voiceController; store: root }
    readonly property alias grokVoice: grokController
    GrokVoice { id: grokController; store: root }
    VoiceOverlay { voice: grokController; liveConversation: true }
    readonly property bool voiceActive: grokController.listeningEnabled || voiceController.listeningEnabled
    readonly property string activeVoicePhase: grokController.listeningEnabled ? grokController.phase : voiceController.phase
    readonly property string activeVoiceName: grokController.wakeEnabled ? "Hey Saturn → Grok" : "Grok live"
    function showPulse(view) {
        if(view === "close") { eachWindow(w => { w.commandOpen=false; w.dashboardOpen=false; w.close(); }); return; }
        eachWindow(w => {
            w.workspacePanel.messagesOpen=false; w.workspacePanel.assistantOpen=false;
            w.workspacePanel.connectionsOpen=false; w.workspacePanel.insights=false;
            if(view === "messages") w.workspacePanel.messagesOpen=true;
            else if(view === "assistant") w.workspacePanel.assistantOpen=true;
            else if(view === "connections") w.workspacePanel.connectionsOpen=true;
            else if(view === "insights") w.workspacePanel.insights=true;
            w.commandOpen=false; w.dashboardOpen=false; w.pinned=true; w.open();
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
        if (calendarSource === "off") return;
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
            } catch (e) { root.agenda = []; root.agendaDays = []; }
        }
        onLoadFailed: { if(root.calendarSource === "omacal") { root.agenda = []; root.agendaDays = []; } }
    }
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
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
            return JSON.stringify({opened: !!w && (w.expanded || w.dashboardOpen || w.commandOpen), running: root.focusState.running, timer: root.timerText, voiceEnabled: root.voiceActive, voicePhase: root.activeVoicePhase, voiceName:root.activeVoiceName});
        }
        function barAction(screen: string, action: string): void {
            var w = root.windowForScreen(screen);
            if (!w) return;
            var opened = w.expanded || w.dashboardOpen || w.commandOpen;
            if (action === "hover") {
                if (!opened) { w.pinned = false; w.open(); }
            } else if (action === "dashboard") w.openDashboard();
            else if (action === "close" || (action === "click" && opened && w.pinned)) {
                w.commandOpen = false; w.dashboardOpen = false; w.close();
            } else if (action === "open" || action === "click") {
                w.pinned = true; w.open();
            }
        }
        function open(): void { root.eachWindow(w => { w.pinned = true; w.open(); }); }
        function close(): void { root.eachWindow(w => { w.commandOpen = false; w.dashboardOpen = false; w.close(); }); }
        function dashboard(): void { if (windows.count > 0) windows.objectAt(0).openDashboard(); }
        function assistant(): void { root.eachWindow(w => { w.pinned = true; w.open(); w.workspacePanel.assistantOpen = true; }); }
        function toggle(): void { root.eachWindow(w => { if (w.commandOpen) w.commandOpen = false; else w.openCommand(); }); }
        function command(): void { root.eachWindow(w => w.openCommand()); }
        function tab(name: string): void { root.eachWindow(w => { w.workspacePanel.insights = name === "Insights"; w.pinned = true; w.open(); }); }
        function tasks(command: string, first: string, second: string): string {
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
            return JSON.stringify({ok: false, error: "Unknown task command"});
        }
        function status(): string {
            var panels = []; root.eachWindow(w => panels.push({screen: w.screen.name, expanded: w.expanded, dashboard: w.dashboardOpen, command: w.commandOpen, timerPopout: w.timerPopout.visible, tab: w.currentTab, hovered: w.hovered}));
            return JSON.stringify({ready: root.ready, error: root.error, schema: root.workspace.version, tasks: root.tasks.length, remaining: root.remainingTasks, archived: root.tasks.filter(t => t.archived).length, mailSource: root.mailSource, calendarSource: root.calendarSource, running: root.focusState.running, timer: root.timerText, agendaEvents: root.agenda.length, calendarDays: root.agendaDays.length, windows: panels});
        }
        function messages(): void { root.eachWindow(w => { w.pinned=true; w.open(); w.workspacePanel.messagesOpen=true; }); }
        function connections(): void { root.eachWindow(w => { w.pinned=true; w.open(); w.workspacePanel.connectionsOpen=true; }); }
        function mailStatus(): string { return JSON.stringify({provider:root.mailSource,connected: root.mail.connected, authenticated: root.mail.authenticated, newForYou: root.newMail.length, busy: root.mail.busy, error: root.mail.lastError}); }
        function messageStatus(): string { return JSON.stringify({sources:{texts:root.messages.textsEnabled,slack:root.messages.slackEnabled,beeper:root.messages.beeperEnabled},keyOnly:root.messages.keyOnly,keepAlerts:root.messages.keepAlerts,conversations:root.messages.rows.length,filtered:root.messages.hiddenCount,busy:root.messages.busy,error:root.messages.error}); }
        function voiceEnable(): void { root.grokVoice.setEnabled(true); }
        function voiceWakeEnable(): void { root.grokVoice.enableWake(); }
        function voiceDisable(): void { root.voice.setEnabled(false); root.grokVoice.setEnabled(false); }
        function voiceToggle(): void { root.grokVoice.talk(); }
        function voiceStop(): void { root.grokVoice.endConversation(); }
        function grokStart(): void { root.grokVoice.setEnabled(true); }
        function grokStop(): void { root.grokVoice.setEnabled(false); }
        function grokStatus(): string { return JSON.stringify({configured:root.grokVoice.configured,ready:root.grokVoice.ready,enabled:root.grokVoice.listeningEnabled,state:root.grokVoice.phase,duplex:root.grokVoice.duplex,latencyMs:root.grokVoice.latencyMs,error:root.grokVoice.error}); }
        function voiceStatus(): string { return JSON.stringify({enabled:root.voiceActive,state:root.activeVoicePhase,provider:root.activeVoiceName,wakeEnabled:root.grokVoice.wakeEnabled,localEnabled:false,grokEnabled:root.grokVoice.listeningEnabled,error:root.grokVoice.error}); }
    }
    Control { target: "saturn" }
    Control { target: "omapulse" } // Deprecated aliases for existing shortcuts.
    Control { target: "omaowl" }
    Component.onDestruction: flush()
}
