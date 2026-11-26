pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Logic.js" as Logic
import "Dates.js" as Dates
import "Slogans.js" as Slogans
import "Notes.js" as Notes
import "Visual.js" as Visual

PanelWindow {
    id: dash
    Theme { id: theme }
    required property var store
    signal dismissed()
    signal expandRequested()
    property bool compact: false
    property bool pinned: false
    property int sloganIndex: Math.floor(Math.random() * Slogans.lines.length)
    readonly property string slogan: Slogans.lines[dash.sloganIndex % Slogans.lines.length]
    property bool awaitingEntry: false
    readonly property bool hovered: workspaceHover.hovered
    readonly property bool editing: taskInput.activeFocus || dueInput.activeFocus || notes.activeFocus || minutesInput.activeFocus || eventTitle.activeFocus || eventStart.activeFocus || connectionsOpen || notesOpen || notesView === "edit"
    readonly property real uiScale: compact ? 0.82 : 1
    property string taskView: "Today"
    property bool insights: false
    property bool notesOpen: false
    property bool notesLoaded: false
    onNotesOpenChanged: if (notesOpen) {
        connectionsOpen = false; insights = false;
        focusedCard = "notes";
        if (store.notesSelection) viewNote(store.notesSelection);
        else showNotes("board");
        notesOpen = false;
    }
    property bool connectionsOpen: false
    property bool connectionsLoaded: false
    onConnectionsOpenChanged: if (connectionsOpen) { notesOpen=false; insights=false; connectionsLoaded=true; }
    property bool mailLoaded: false
    onInsightsChanged: if (insights) { notesOpen=false; connectionsOpen=false; }
    // Empty means the five-card grid. A role means that card has expanded to
    // the full workspace; no separate collapsed window exists.
    property string focusedCard: ""
    // Panel navigation survives closing and reopening. Guards keep the normal
    // view handlers from resetting a restored card on the way in.
    property bool restoringState: false
    property bool stateRestored: false
    readonly property var switchRoles: ["tasks", "notes", "focus", "events", "mail"].filter(function(role) { return role !== dash.focusedCard; })
    function cardColor(role) {
        if (role === "tasks") return theme.tasks;
        if (role === "notes") return theme.notes;
        if (role === "focus") return theme.focus;
        if (role === "events") return theme.events;
        return theme.mail;
    }
    function roleLabel(role) {
        return ({tasks: "Tasks", notes: "Notepad", focus: "Focus", events: "Events", mail: "Mail"})[role] || role;
    }
    function roleIcon(role) {
        return ({tasks: "list-todo", notes: "notebook-pen", focus: "play", events: "calendar", mail: "mail"})[role] || "link";
    }
    function roleCaption(role) {
        if (role === "tasks") return dash.store.remainingTasks + " to do";
        if (role === "notes") return dash.dayNotes.length + " linked";
        if (role === "focus") return dash.store.timerText;
        if (role === "events") return dash.store.agenda.length + " today";
        return dash.store.newMail.length + " new";
    }
    property bool frosted: true
    property bool frostReady: false
    // Saturn belongs to the workspace it was opened on. Leaving that workspace
    // dismisses it instead of leaving a full-screen layer on the new one.
    property int openedWorkspace: -1
    readonly property int activeWorkspaceId: {
        var monitor = Hyprland.monitorFor(dash.screen);
        return monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1;
    }
    onActiveWorkspaceIdChanged: {
        if (!visible) return;
        if (openedWorkspace === -1) { openedWorkspace = activeWorkspaceId; return; }
        if (activeWorkspaceId !== -1 && activeWorkspaceId !== openedWorkspace) dash.close();
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "workspacev2" || event.name === "focusedmonv2")
                workspaceCheck.restart();
        }
    }
    Timer {
        id: workspaceCheck
        interval: 100
        onTriggered: {
            var monitor = Hyprland.monitorFor(dash.screen);
            var current = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1;
            if (dash.visible && dash.openedWorkspace !== -1 && current !== -1 && current !== dash.openedWorkspace)
                dash.close();
        }
    }
    readonly property int taskAttention: Visual.attention(dash.store.tasks, dash.store.today, 0).level
    readonly property var dayNotes: {
        store.revision;
        return store.notesForDay(store.noteDay);
    }
    property string calendarDate: store.calendarToday
    readonly property int calendarIndex: store.agendaDays.findIndex(d => d.date === dash.calendarDate)
    readonly property var calendarDay: store.agendaDays[Math.max(0, calendarIndex)] || null
    readonly property var baseRows: Logic.tasksInView(dash.store.tasks, dash.taskView, dash.store.today)
    property string taskTag: ""
    readonly property var tagCloud: Logic.tagCloud(dash.store.tasks)
    readonly property var taskRows: Logic.withTag(dash.baseRows, dash.taskTag)
    readonly property var taskGroups: Logic.taskGroups(dash.taskRows, dash.store.today)
    // One flat model: a date header, then the tasks created that day. Keeping
    // headers in the model avoids ListView section quirks with this delegate.
    readonly property var taskItems: {
        var out = [];
        dash.taskGroups.forEach(function(group) {
            out.push({ group: true, key: group.key, label: group.label, count: group.tasks.length });
            group.tasks.forEach(function(task) { out.push({ group: false, key: group.key, task: task }); });
        });
        return out;
    }
    readonly property var selectedTask: dash.store.tasks.find(t => t.id === dash.selectedTaskId) || null
    property string selectedTaskId: ""
    property string editingTaskId: ""
    property string dueTaskId: ""
    property string taskDraft: ""
    property string dueDraft: ""
    property var graphRelated: []
    readonly property var noteTints: [
        Qt.rgba(0.36, 0.55, 0.94, 1),
        Qt.rgba(0.34, 0.78, 0.52, 1),
        Qt.rgba(0.69, 0.49, 1.00, 1),
        Qt.rgba(0.90, 0.72, 0.36, 1),
        Qt.rgba(0.88, 0.42, 0.46, 1),
        Qt.rgba(0.50, 0.82, 0.90, 1)
    ]
    readonly property var allNotes: {
        dash.store.revision;
        return dash.store.searchNotes("", 100).filter(function(note) { return !note.archived; });
    }
    function noteTint(id) {
        var text = String(id || ""), hash = 0;
        for (var i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
        return dash.noteTints[hash % dash.noteTints.length];
    }
    function noteDate(note) {
        return note && note.date ? Qt.formatDate(new Date(note.date + "T12:00:00"), "d MMM") : "Undated";
    }
    function openWikiLink(title) {
        var task = (dash.store.tasks || []).find(function(item) { return item.title === title; });
        if (task) {
            dash.focusedCard = "tasks";
            dash.selectedTaskId = task.id;
            return;
        }
        var note = (dash.store.workspace.notesV2 || []).find(function(item) { return item.title === title; });
        if (note) {
            dash.viewNote(note.id);
        }
    }
    // Notepad views: write (daily editor + dated notes), board (full-card grid),
    // note (one note full-card). The top-level Notes surface has its own editor.
    property string notesView: "write"
    property string openNoteId: ""
    readonly property var openNote: {
        dash.store.revision;
        return dash.allNotes.find(function(note) { return note.id === dash.openNoteId; }) || null;
    }
    function showNotes(view) {
        dash.notesView = view;
        if (view !== "note") dash.openNoteId = "";
    }
    function viewNote(id) {
        if (!id) return;
        dash.focusedCard = "notes";
        dash.openNoteId = id;
        dash.notesLoaded = true;
        dash.notesView = "edit";
        Qt.callLater(function() {
            var pane = notesLoader.item as NotesPane;
            if (pane) pane.select(dash.openNote);
        });
    }
    function returnToBoard() {
        if (dash.notesView === "edit") {
            var pane = notesLoader.item as NotesPane;
            if (pane) pane.save(true);
        }
        dash.showNotes("board");
    }
    function browseNote(offset) {
        var index = dash.allNotes.findIndex(function(note) { return note.id === dash.openNoteId; });
        var target = dash.allNotes[index + offset];
        if (!target) return;
        if (dash.notesView === "edit") {
            var pane = notesLoader.item as NotesPane;
            if (pane) pane.save(true);
        }
        dash.viewNote(target.id);
    }
    readonly property int openNoteIndex: dash.allNotes.findIndex(function(note) { return note.id === dash.openNoteId; })
    property string pendingNoteDay: ""
    function createNoteForDay(day) {
        if (dash.notesView === "edit") {
            var current = notesLoader.item as NotesPane;
            if (current) current.save(true);
        }
        dash.openNoteId = "";
        dash.pendingNoteDay = day;
        dash.notesLoaded = true;
        dash.focusedCard = "notes";
        dash.notesView = "edit";
        var pane = notesLoader.item as NotesPane;
        if (pane) {
            pane.createForDay(day);
            dash.pendingNoteDay = "";
        }
    }
    readonly property string graphScript: Qt.resolvedUrl("scripts/saturn_graph.py").toString().replace("file://", "")
    property Process graphQuery: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var payload = JSON.parse(text || "{}");
                    dash.graphRelated = (payload.nodes || []).filter(function(node) {
                        return node.kind !== "tag" && node.key !== payload.root;
                    }).slice(0, 6);
                } catch (error) {
                    dash.graphRelated = [];
                }
            }
        }
    }
    function taskCount(view) {
        var rows = Logic.tasksInView(dash.store.tasks, view, dash.store.today);
        return Logic.withTag(rows, dash.taskTag).length;
    }
    function toggleTag(tag) {
        if (!tag) return;
        dash.taskTag = dash.taskTag === tag ? "" : tag;
        Qt.callLater(dash.selectFirstTask);
    }
    function clearTag() {
        dash.taskTag = "";
        Qt.callLater(dash.selectFirstTask);
    }
    // Tag cloud sizes follow frequency: the themes you use most read first.
    function tagSize(count) {
        if (count >= 6) return 21;
        if (count >= 4) return 18;
        if (count >= 2) return 15;
        return 13;
    }
    function openTag(tag) {
        if (!tag) return;
        dash.taskTag = tag;
        dash.taskView = "All";
        Qt.callLater(dash.selectFirstTask);
    }
    function focusTask(id) {
        if (!id) return;
        dash.taskTag = "";
        dash.selectedTaskId = id;
        Qt.callLater(function() {
            var index = dash.taskItems.findIndex(function(item) { return !item.group && item.task.id === id; });
            if (index >= 0) taskList.positionViewAtIndex(index, ListView.Contain);
        });
    }
    function openRelated(node) {
        if (!node) return;
        var id = String(node.key).split(":")[1];
        if (node.kind === "task") focusTask(id);
        else if (node.kind === "note" || node.kind === "daily") {
            dash.notesLoaded = true;
            dash.notesOpen = true;
            dash.store.showPulse("notes", id);
        }
    }
    function refreshGraph() {
        dash.graphRelated = [];
        if (!dash.selectedTaskId) return;
        graphQuery.exec(["python3", dash.graphScript, "neighbors", "task:" + dash.selectedTaskId, "1"]);
    }
    function editTask(task) {
        if (!task) return;
        dash.selectedTaskId = task.id;
        dash.editingTaskId = task.id;
        dash.taskDraft = task.title || "";
    }
    function editDue(task) {
        if (!task) return;
        dash.selectedTaskId = task.id;
        dash.dueTaskId = task.id;
        dash.dueDraft = task.due || "";
    }
    function commitTask() {
        if (!dash.editingTaskId) return;
        dash.store.renameTask(dash.editingTaskId, dash.taskDraft);
        dash.editingTaskId = "";
    }
    function commitDue() {
        if (!dash.dueTaskId) return;
        dash.store.setTaskDue(dash.dueTaskId, dash.dueDraft);
        dash.dueTaskId = "";
    }
    function selectFirstTask() {
        var first = dash.taskItems.find(function(item) { return !item.group; });
        dash.selectedTaskId = first ? first.task.id : "";
    }
    // Escape has to work even when a text field owns focus, so it also exists as
    // a window shortcut instead of only on the page's key handler.
    function handleEscape() {
        if (dash.editingTaskId) { dash.editingTaskId = ""; return; }
        if (dash.dueTaskId) { dash.dueTaskId = ""; return; }
        if (dash.focusedCard === "notes" && dash.notesView !== "board") { dash.returnToBoard(); return; }
        if (dash.focusedCard) { dash.focusedCard = ""; return; }
        dash.close();
    }
    onTaskViewChanged: {
        if (dash.restoringState) return;
        if (taskView === "Tags") selectedTaskId = "";
        else Qt.callLater(selectFirstTask);
    }
    onSelectedTaskIdChanged: dash.refreshGraph()
    onFocusedCardChanged: {
        if (focusedCard === "mail") mailLoaded = true;
        if (dash.restoringState) return;
        if (focusedCard === "notes") notesView = "board";
        if (focusedCard !== "notes") { notesView = "write"; openNoteId = ""; }
        if (focusedCard === "tasks") {
            if (taskView !== "Tags" && !selectedTaskId) selectFirstTask();
            Qt.callLater(function() { taskList.positionViewAtBeginning(); });
        }
    }
    function submitEvent() {
        var title = eventTitle.text.trim();
        if (!title) return;
        var start = eventStart.text.trim() || (dash.calendarDate + "T09:00");
        dash.store.addEvent(title, start, "");
        eventTitle.text = ""; eventStart.text = "";
        page.forceActiveFocus();
    }
    function submitTask() {
        var text = taskInput.text.trim();
        if (!text) return;
        dash.store.addTask(text, dueInput.text.trim());
        taskInput.text = ""; dueInput.text = "";
        page.forceActiveFocus();
    }
    readonly property color textColor: theme.text
    anchors { top: true; bottom: !dash.compact; left: !dash.compact; right: !dash.compact }
    margins.top: compact ? Style.bar.sizeHorizontal + 5 : 0
    implicitWidth: compact ? Math.min(1880, screen.width - 32) : screen.width
    implicitHeight: compact ? Math.min(520, screen.height - 80) : screen.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: compact ? "saturn-workspace" : "saturn-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    onVisibleChanged: {
        if (!visible) {
            dash.saveState();
            frostReady = false; frostLoader.active = false;
            focusedCard = ""; editingTaskId = ""; dueTaskId = "";
            stateRestored = false;
            return;
        }
        openedWorkspace = activeWorkspaceId;
        dash.restoreState();
        awaitingEntry = compact; page.forceActiveFocus(); store.mail.refreshIfStale();
        if(store.calendarSource === "google") store.googleCalendar.refreshIfStale();
        if (compact && !pinned) leaveTimer.restart();
        frostTimer.restart();
    }
    onFrostedChanged: if (frosted && visible) frostTimer.restart(); else frostLoader.active = false
    // Capture one still frame when the panel opens. No pointer-following loop.
    Timer { id: frostTimer; interval: 60; onTriggered: if (dash.frosted && dash.visible) frostLoader.active = true }
    onEditingChanged: if (!editing && !hovered) leaveTimer.restart()
    Timer { id: leaveTimer; interval: dash.awaitingEntry ? 1200 : 700; onTriggered: if (dash.compact && dash.visible && !dash.hovered && !dash.pinned && !dash.editing) dash.close() }
    // Frosted backdrop: one still screencopy, blurred once, never per frame.
    // It is opt-out with the Frost button and stays opaque until capture lands.
    Loader {
        id: frostLoader; active: false; anchors.fill: parent; z: 0
        sourceComponent: Component {
            Item {
                ScreencopyView {
                    id: frostShot; anchors.fill: parent; visible: false; live: false
                    captureSource: dash.screen
                    onHasContentChanged: if (hasContent) dash.frostReady = true
                }
                MultiEffect {
                    anchors.fill: parent; visible: frostShot.hasContent
                    source: frostShot; autoPaddingEnabled: false
                    blurEnabled: true; blur: 0.55; blurMax: 40; blurMultiplier: 1
                }
                Rectangle { anchors.fill: parent; color: theme.background; opacity: 0.05 }
            }
        }
    }
    Rectangle {
        anchors.fill: parent; z: 1
        color: dash.frosted && dash.frostReady ? theme.alpha(theme.background, 0.48) : theme.background
        radius: 0
        Behavior on color { ColorAnimation { duration: Style.duration(160) } }
    }
    function saveState() {
        if (!dash.store || !dash.store.storagePrepared) return;
        dash.store.saveUiState(dash.screen.name, {
            focusedCard: dash.focusedCard,
            notesView: dash.notesView,
            openNoteId: dash.openNoteId,
            taskView: dash.taskView,
            selectedTaskId: dash.selectedTaskId,
            taskTag: dash.taskTag,
            calendarDate: dash.calendarDate,
            noteDay: dash.store.noteDay,
            insights: dash.insights,
            connectionsOpen: dash.connectionsOpen,
            frosted: dash.frosted
        });
    }
    function restoreState() {
        if (dash.stateRestored || !dash.store || !dash.store.storagePrepared) return;
        var saved = dash.store.uiStateFor(dash.screen.name);
        if (!saved || Object.keys(saved).length === 0) return;
        dash.restoringState = true;
        dash.connectionsOpen = !!saved.connectionsOpen;
        dash.insights = !!saved.insights;
        dash.taskView = saved.taskView || "Today";
        dash.selectedTaskId = saved.selectedTaskId || "";
        dash.taskTag = saved.taskTag || "";
        dash.calendarDate = saved.calendarDate || dash.store.calendarToday;
        dash.store.noteDay = saved.noteDay || dash.store.today;
        dash.frosted = saved.frosted !== false;
        dash.focusedCard = saved.focusedCard || "";
        if (dash.focusedCard === "notes" && saved.notesView === "edit" && saved.openNoteId) {
            dash.viewNote(saved.openNoteId);
        } else {
            dash.notesView = saved.notesView === "write" ? "write" : "board";
            dash.openNoteId = "";
        }
        dash.restoringState = false;
        dash.stateRestored = true;
        if (dash.focusedCard === "tasks" && !dash.selectedTaskId) Qt.callLater(selectFirstTask);
    }
    function close() { dash.saveState(); store.flush(); dismissed(); }
    function moveDay(offset) {
        var index = Math.max(0, calendarIndex) + offset;
        if (index >= 0 && index < store.agendaDays.length) calendarDate = store.agendaDays[index].date;
    }
    function eventClock(ms) { return store.calendarClocks[String(ms)] || Qt.formatTime(new Date(ms), "h:mm AP"); }
    Connections {
        target: dash.store
        function onUiStateChanged() { if (dash.visible && !dash.stateRestored) dash.restoreState(); }
        function onAgendaDaysChanged() { if(dash.store.agendaDays.length && !dash.store.agendaDays.some(d=>d.date === dash.calendarDate)) dash.calendarDate=dash.store.agendaDays[0].date; }
        function onTaskAdded(title) { if (taskInput.text.trim() === title) { taskInput.text = ""; dueInput.text = ""; } }
    }

    component Label: Text {
        color: dash.textColor; font.family: theme.font; font.pixelSize: 16
        textFormat: Text.PlainText; elide: Text.ElideRight
    }
    component Action: AbstractButton {
        id: action
        property bool selected: false
        property bool dark: false
        implicitHeight: 38
        implicitWidth: Math.max(38, label.implicitWidth + 24)
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        background: Rectangle { radius: 3; color: action.dark ? (action.selected ? theme.accent : action.hovered ? theme.border : theme.raised) : action.selected ? theme.accent : action.hovered ? theme.hover : theme.raised; opacity: action.enabled ? 1 : 0.4 }
        contentItem: Label { id: label; text: action.text; font.pixelSize: 14; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: action.dark ? (action.selected ? theme.background : theme.text) : action.selected ? theme.background : dash.textColor }
    }
    // Borderless card: separation comes from surface contrast and spacing.
    // Volume is exposed as physical stack layers; urgency is one dot; the
    // expand control moves the card to the full workspace and back.
    component Card: Item {
        id: card
        property string role: ""
        property int volume: 0
        property int attention: 0
        property color color: theme.surface
        property bool focused: dash.focusedCard === card.role
        property bool hovered: cardHover.hovered
        property real stackLift: card.hovered && !dash.focusedCard ? 3 : 0
        default property alias content: body.data
        opacity: dash.focusedCard && !card.focused ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

        Rectangle {
            id: surface
            anchors.fill: parent; radius: 6; color: card.color
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                height: 1; color: theme.alpha(theme.text, card.hovered || card.focused ? 0.18 : 0.08)
            }
        }
        Item { id: body; anchors.fill: parent }
        HoverHandler { id: cardHover; cursorShape: Qt.ArrowCursor }
        Rectangle {
            anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 14; z: 3
            width: 8; height: 8; radius: 4
            color: card.attention === 2 ? theme.urgent : theme.accent
            visible: card.attention > 0
            opacity: card.hovered ? 1 : 0.75
        }
        AbstractButton {
            id: expand
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10; z: 4
            width: 30; height: 30
            hoverEnabled: true; focusPolicy: Qt.NoFocus
            opacity: card.hovered || card.focused ? 1 : 0.32
            Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
            onClicked: {
                if (card.role === "notes" && card.focused && dash.notesView !== "board") dash.returnToBoard();
                else dash.focusedCard = card.focused ? "" : card.role;
            }
            Accessible.name: card.focused ? "Return to workspace" : "Expand " + card.role
            ToolTip.visible: hovered; ToolTip.text: card.focused ? "Back to workspace (Esc)" : "Expand"
            contentItem: Label {
                text: card.focused ? "×" : "⤢"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                color: theme.text; font.pixelSize: 15
            }
            background: Rectangle { radius: 3; color: expand.hovered ? theme.alpha(theme.text, 0.1) : "transparent" }
        }
    }
    component CardHeading: RowLayout {
        id: heading
        property string text: ""
        property string icon: ""
        spacing: 9
        Icon { name: heading.icon; size: 18; tint: theme.alpha(theme.text, 0.72) }
        Label { text: heading.text; font.pixelSize: 18; font.weight: Font.DemiBold }
        Item { Layout.fillWidth: true }
    }
    // Text-first controls. No filled button chrome unless the surface itself is
    // the target (the timer dial).
    component Tab: AbstractButton {
        id: tab
        property bool selected: false
        implicitHeight: 30
        implicitWidth: Math.max(28, tabLabel.implicitWidth + 14)
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        background: Item {
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 2; color: tab.selected ? theme.accent : tab.hovered ? theme.alpha(theme.text, 0.28) : "transparent"
                Behavior on color { ColorAnimation { duration: Style.duration(140) } }
            }
        }
        contentItem: Label {
            id: tabLabel; text: tab.text; font.pixelSize: 14
            font.weight: tab.selected ? Font.DemiBold : Font.Normal
            color: tab.selected ? theme.text : tab.hovered ? theme.text : theme.muted
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
    component NoteTab: AbstractButton {
        id: noteTab
        property string iconName: ""
        property bool selected: false
        implicitHeight: 36
        implicitWidth: tabContent.implicitWidth + 18
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        background: Item {
            Rectangle {
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12; height: 2
                color: noteTab.selected ? theme.accent : "transparent"
            }
        }
        contentItem: RowLayout {
            id: tabContent
            spacing: 7
            Icon { name: noteTab.iconName; size: 14; tint: noteTab.selected ? theme.text : theme.alpha(theme.text, 0.66) }
            Label {
                text: noteTab.text; font.pixelSize: 13
                font.weight: noteTab.selected ? Font.DemiBold : Font.Normal
                color: noteTab.selected || noteTab.hovered ? theme.text : theme.alpha(theme.text, 0.68)
            }
        }
    }
    component DayArrow: AbstractButton {
        id: dayArrow
        property string iconName: ""
        implicitWidth: 34; implicitHeight: 34
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        opacity: enabled ? 1 : 0.3
        background: Rectangle { radius: 4; color: dayArrow.hovered ? theme.alpha(theme.text, 0.07) : "transparent" }
        contentItem: Item {
            Icon { name: dayArrow.iconName; size: 14; tint: theme.text; anchors.centerIn: parent }
        }
    }
    component NewNoteButton: AbstractButton {
        id: newNoteButton
        text: "New note"
        implicitHeight: 36
        implicitWidth: newNoteContent.implicitWidth + 20
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        background: Rectangle {
            radius: 5
            color: newNoteButton.hovered ? theme.alpha(theme.text, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
        }
        contentItem: RowLayout {
            id: newNoteContent
            spacing: 7
            Icon { name: "plus"; size: 15; tint: theme.text }
            Label { text: newNoteButton.text; font.pixelSize: 13; font.weight: Font.DemiBold; color: theme.text }
        }
    }
    component Glyph: AbstractButton {
        id: glyph
        implicitWidth: 28; implicitHeight: 28
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        opacity: enabled ? 1 : 0.35
        background: Rectangle { radius: 3; color: glyph.hovered ? theme.alpha(theme.text, 0.1) : "transparent" }
        contentItem: Label {
            text: glyph.text; font.pixelSize: 14
            color: glyph.hovered ? theme.text : theme.muted
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
    // Lucide-style strokes, tinted through MultiEffect so the icon follows the
    // theme instead of being locked to the white baked into the SVG.
    component Icon: Item {
        id: iconRoot
        property string name: ""
        property color tint: theme.text
        property real size: 16
        implicitWidth: size; implicitHeight: size
        Image {
            id: iconSource
            anchors.fill: parent
            visible: false
            source: Qt.resolvedUrl("assets/icons/" + iconRoot.name + ".svg")
            fillMode: Image.PreserveAspectFit
            sourceSize.width: iconRoot.size * 2; sourceSize.height: iconRoot.size * 2
        }
        MultiEffect {
            anchors.fill: parent
            source: iconSource
            colorizationColor: iconRoot.tint
            colorization: 1
            brightness: 0
        }
    }
    component IconButton: AbstractButton {
        id: iconButton
        property string iconName: ""
        property string label: ""
        property real iconSize: 15
        implicitWidth: 28; implicitHeight: 28
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        opacity: enabled ? 1 : 0.35
        background: Rectangle { radius: 4; color: iconButton.hovered ? theme.alpha(theme.text, 0.1) : "transparent" }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                width: iconButton.iconSize; height: iconButton.iconSize
                name: iconButton.iconName
                tint: iconButton.hovered ? theme.text : theme.alpha(theme.text, 0.62)
            }
        }
        Accessible.name: label
    }
    // Icon + label pairs for the detail pane actions. Text alone was ambiguous;
    // the icon carries the verb and the label carries the object.
    component ActionButton: Item {
        id: action
        property string icon: ""
        property string text: ""
        signal clicked()
        readonly property alias hovered: actionHover.hovered
        implicitWidth: actionRow.implicitWidth + 18
        implicitHeight: 30
        Rectangle {
            anchors.fill: parent; radius: 4
            color: action.hovered ? theme.hover : "transparent"
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
        }
        Row {
            id: actionRow
            anchors.centerIn: parent; spacing: 7
            Icon { name: action.icon; size: 14; tint: action.hovered ? theme.text : theme.alpha(theme.text, 0.72) }
            Label { text: action.text; font.pixelSize: 13; color: action.hovered ? theme.text : theme.alpha(theme.text, 0.72) }
        }
        HoverHandler { id: actionHover }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: action.clicked() }
        Accessible.name: text
    }

    component Dial: Item {
        id: dial
        property real progress: 0
        property string time: "00:00"
        property string hint: ""
        signal toggled()
        implicitHeight: 180
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) - 20
            height: width; radius: width / 2
            color: "transparent"; border.width: 5
            border.color: theme.alpha(theme.text, 0.18)
        }
        Canvas {
            id: ring
            anchors.fill: parent
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var c = width / 2, r = Math.min(width, height) / 2 - 10;
                ctx.lineWidth = 5;
                ctx.strokeStyle = theme.alpha(theme.text, 0.24);
                ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke();
                var p = Math.max(0, Math.min(1, dial.progress));
                if (p > 0) {
                    ctx.strokeStyle = theme.accent;
                    ctx.lineCap = "round";
                    ctx.beginPath();
                    ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p);
                    ctx.stroke();
                }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 4
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.time; font.family: "monospace"; font.pixelSize: 46; font.letterSpacing: 1
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.hint; font.pixelSize: 11; color: theme.muted
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dial.toggled()
        }
        onProgressChanged: ring.requestPaint()
        onWidthChanged: ring.requestPaint()
        onHeightChanged: ring.requestPaint()
        Component.onCompleted: ring.requestPaint()
    }
    component Entry: TextField {
        color: dash.textColor; font.family: theme.font; font.pixelSize: 16
        placeholderTextColor: theme.muted; padding: 12; implicitHeight: 48
        selectionColor: theme.accent; selectedTextColor: theme.background
        background: Rectangle { radius: 3; color: theme.raised; border.width: parent.activeFocus ? 1 : 0; border.color: theme.accent }
    }

    FocusScope {
        id: page; anchors.fill: parent; focus: true; z: 2
        HoverHandler { id: workspaceHover; onHoveredChanged: { if (hovered) { dash.awaitingEntry = false; leaveTimer.stop(); } else leaveTimer.restart(); } }
        Shortcut {
            sequence: "Escape"
            context: Qt.WindowShortcut
            onActivated: dash.handleEscape()
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                dash.handleEscape();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_N && !dash.editing) {
                dash.focusedCard = ""; dash.taskView = "Today"; taskInput.forceActiveFocus(); event.accepted = true; return;
            }
            if (event.key === Qt.Key_0) { dash.focusedCard = ""; event.accepted = true; return; }
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                var roles = ["tasks", "notes", "focus", "events", "mail"];
                dash.focusedCard = roles[event.key - Qt.Key_1]; event.accepted = true;
            }
        }
        Timer {
            interval: 9000; running: dash.visible; repeat: true
            onTriggered: dash.sloganIndex = (dash.sloganIndex + 1) % Slogans.lines.length
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: (dash.compact ? parent.width - 30 : Math.min(2100, parent.width - 80)) / dash.uiScale
            height: (dash.compact ? parent.height - 30 : Math.min(980, parent.height - 100)) / dash.uiScale
            scale: dash.uiScale
            spacing: 25
            RowLayout {
                Layout.fillWidth: true
                Image { Layout.preferredWidth: 46; Layout.preferredHeight: 46; source: Qt.resolvedUrl("assets/saturn.png"); fillMode: Image.PreserveAspectFit; sourceSize.width: 92; sourceSize.height: 92; mipmap: true }
                ColumnLayout {
                    spacing: 3
                    Label { text: "Saturn"; color: theme.text; font.pixelSize: 27; font.weight: Font.DemiBold }
                    Label {
                        id: sloganLabel
                        Layout.maximumWidth: 640
                        text: dash.slogan
                        color: theme.muted; font.pixelSize: 13
                        elide: Text.ElideRight
                        onTextChanged: sloganFade.restart()
                        NumberAnimation {
                            id: sloganFade; target: sloganLabel; property: "opacity"
                            from: 0.35; to: 1; duration: Style.duration(320); easing.type: Easing.OutCubic
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Tab { text: "Workspace"; selected: !dash.insights && !dash.connectionsOpen && !dash.notesOpen; onClicked: { dash.focusedCard = ""; dash.notesOpen = false; dash.insights = false; dash.connectionsOpen = false; } }
                Tab { text: "Insights"; selected: dash.insights; onClicked: { dash.focusedCard = ""; dash.insights = true; dash.connectionsOpen = false; } }
                Tab { text: "Connections"; selected: dash.connectionsOpen; onClicked: { dash.focusedCard = ""; dash.connectionsOpen = true; dash.insights = false; } }
                Tab { text: dash.frosted ? "Frost" : "Frost off"; selected: dash.frosted; onClicked: dash.frosted = !dash.frosted; ToolTip.visible: hovered; ToolTip.text: "Blur the desktop behind the workspace" }
                Glyph { text: "×"; onClicked: dash.close(); Accessible.name: "Close workspace" }
            }
            Item {
                id: workspaceGrid
                visible: !dash.insights && !dash.connectionsOpen && !dash.notesOpen
                onVisibleChanged: if (visible) { opacity = 0; workspaceReveal.start(); }
                Layout.fillWidth: true; Layout.fillHeight: true
                readonly property var slots: Visual.grid(width, height)
                readonly property real switchWidth: Math.max(188, Math.round(width * 0.15))
                function sx(role) { return dash.focusedCard === role ? 0 : slots.cards[role].x }
                function sy(role) { return dash.focusedCard === role ? 0 : slots.cards[role].y }
                function sw(role) { return dash.focusedCard === role ? width - switchWidth - 16 : slots.cards[role].width }
                function sh(role) { return dash.focusedCard === role ? height : slots.cards[role].height }
                NumberAnimation { id: workspaceReveal; target: workspaceGrid; property: "opacity"; from: 0; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
                // A focused card leaves room for the other cards as small switches
                // instead of taking the whole workspace.
                Item {
                    id: switchRail
                    readonly property bool active: dash.focusedCard !== ""
                    x: workspaceGrid.width - workspaceGrid.switchWidth
                    width: workspaceGrid.switchWidth
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    enabled: active
                    opacity: active ? 1 : 0
                    z: 20
                    Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 10; anchors.bottomMargin: 10
                        spacing: 8
                        Repeater {
                            model: dash.switchRoles
                            Rectangle {
                                id: mini
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 58
                                radius: 6
                                color: theme.alpha(theme.text, miniHover.hovered ? 0.07 : 0.02)
                                border.width: 0
                                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                RowLayout {
                                    id: miniContent
                                    anchors.centerIn: parent
                                    width: parent.width - 32
                                    spacing: 10
                                    Icon { name: dash.roleIcon(mini.modelData); size: 16; tint: theme.alpha(theme.text, 0.55); Layout.alignment: Qt.AlignVCenter }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Label { Layout.fillWidth: true; text: dash.roleLabel(mini.modelData); font.pixelSize: 13; color: theme.alpha(theme.text, miniHover.hovered ? 1 : 0.7); elide: Text.ElideRight }
                                        Label { Layout.fillWidth: true; text: dash.roleCaption(mini.modelData); font.pixelSize: 10; color: theme.alpha(theme.text, 0.4); elide: Text.ElideRight }
                                    }
                                }
                                HoverHandler { id: miniHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dash.focusedCard = mini.modelData
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Card {
                    role: "tasks"; volume: Visual.volume(dash.taskRows.length); attention: dash.taskAttention
                    color: theme.tasks
                    x: workspaceGrid.sx("tasks"); y: workspaceGrid.sy("tasks")
                    width: workspaceGrid.sw("tasks"); height: workspaceGrid.sh("tasks")
                    z: dash.focusedCard === "tasks" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "tasks"
                    Item {
                        id: tasksBody
                        anchors.fill: parent
                        // The left pane is a shade darker than the card; the right
                        // pane is the card itself, so content runs edge to edge.
                        Rectangle {
                            id: listSurface
                            visible: dash.focusedCard === "tasks"
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: Math.round(parent.width * 0.40)
                            radius: 6
                            color: theme.alpha(theme.background, 0.15)
                            Rectangle {
                                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: 6; color: parent.color
                            }
                        }
                        Rectangle {
                            id: paneDivider
                            visible: dash.focusedCard === "tasks"
                            x: Math.round(parent.width * 0.40)
                            width: 1
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            color: theme.alpha(theme.text, 0.14)
                        }
                        ColumnLayout {
                            id: taskLeft
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: (dash.focusedCard === "tasks" ? Math.round(parent.width * 0.40) : parent.width) - 48
                            anchors.leftMargin: 24; anchors.topMargin: 35; anchors.bottomMargin: 24
                            spacing: 12
                        CardHeading {
                            Layout.fillWidth: true
                            icon: "list-todo"
                            text: ({Today: "Today’s tasks", Upcoming: "Upcoming", All: "All tasks", Completed: "Completed", Archive: "Archive", Tags: "Tags"})[dash.taskView]
                            Label {
                                text: dash.taskView === "Tags"
                                    ? dash.tagCloud.length + " tags"
                                    : Qt.formatDate(new Date(dash.store.now), "ddd, d MMM") + " · " + dash.taskRows.length + (dash.taskView === "Completed" ? " done" : " to do")
                                font.pixelSize: 12; opacity: 0.7
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Tab { text: "Today " + dash.taskCount("Today"); selected: dash.taskView === "Today"; onClicked: dash.taskView = "Today" }
                            Tab { text: "Upcoming " + dash.taskCount("Upcoming"); selected: dash.taskView === "Upcoming"; onClicked: dash.taskView = "Upcoming" }
                            Tab { text: "All " + dash.taskCount("All"); selected: dash.taskView === "All"; onClicked: dash.taskView = "All" }
                            Tab { text: "Done " + dash.taskCount("Completed"); selected: dash.taskView === "Completed"; onClicked: dash.taskView = "Completed" }
                            Tab { text: "Archive " + dash.taskCount("Archive"); selected: dash.taskView === "Archive"; onClicked: dash.taskView = "Archive" }
                            Tab { text: "Tags " + dash.tagCloud.length; selected: dash.taskView === "Tags"; onClicked: dash.taskView = "Tags" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: dash.taskTag !== "" && dash.taskView !== "Tags"
                            spacing: 6
                            ActionButton {
                                icon: "x"; text: "Clear #" + dash.taskTag
                                onClicked: dash.clearTag()
                            }
                            Label {
                                text: dash.taskRows.length + (dash.taskRows.length === 1 ? " task" : " tasks")
                                font.pixelSize: 11; color: theme.alpha(theme.text, 0.5)
                            }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            ListView {
                                id: taskList
                                anchors.fill: parent
                                visible: dash.taskView !== "Tags"
                                clip: true; spacing: 4; topMargin: 2; bottomMargin: 2
                                model: dash.taskItems
                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded; width: 4
                                    background: null
                                    contentItem: Rectangle { implicitWidth: 4; radius: 2; color: theme.alpha(theme.text, 0.28) }
                                }
                                delegate: Item {
                                    id: taskRow
                                    required property var modelData
                                    property bool isHeader: !!modelData.group
                                    property var task: modelData.task || ({})
                                    property bool hovered: !isHeader && taskHover.hovered
                                    property bool selected: !!task.id && dash.selectedTaskId === task.id
                                    width: ListView.view.width
                                    height: isHeader ? 36 : 46
                                    HoverHandler { id: taskHover; enabled: !taskRow.isHeader }
                                    Item {
                                        visible: taskRow.isHeader
                                        anchors.fill: parent
                                        Label {
                                            anchors.left: parent.left; anchors.bottom: parent.bottom
                                            anchors.leftMargin: 2; anchors.bottomMargin: 4
                                            text: taskRow.isHeader ? String(taskRow.modelData.label || "").toUpperCase() : ""
                                            font.pixelSize: 10; font.letterSpacing: 1.4; font.weight: Font.DemiBold
                                            color: theme.alpha(theme.text, 0.45)
                                        }
                                        Label {
                                            anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.rightMargin: 2; anchors.bottomMargin: 4
                                            text: taskRow.isHeader ? taskRow.modelData.count : ""
                                            font.pixelSize: 10
                                            color: theme.alpha(theme.text, 0.32)
                                        }
                                    }
                                    Rectangle {
                                        visible: !taskRow.isHeader
                                        anchors.fill: parent; radius: 6
                                        color: taskRow.selected ? theme.alpha(theme.accent, 0.08) : taskRow.hovered ? theme.alpha(theme.text, 0.03) : "transparent"
                                        border.width: 1
                                        border.color: taskRow.selected ? theme.alpha(theme.accent, 0.50)
                                                                      : taskRow.hovered ? theme.alpha(theme.text, 0.18)
                                                                                        : theme.alpha(theme.text, 0.10)
                                        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                                        Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; acceptedButtons: Qt.LeftButton
                                        enabled: !taskRow.isHeader
                                        onClicked: dash.selectedTaskId = taskRow.task.id
                                    }
                                    RowLayout {
                                        visible: !taskRow.isHeader
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 6
                                        spacing: 10
                                        Item {
                                            id: taskCheck
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            Rectangle {
                                                anchors.centerIn: parent; width: 17; height: 17; radius: 9
                                                color: taskRow.task.done ? theme.accent : "transparent"
                                                border.width: 1
                                                border.color: taskRow.task.done ? theme.accent : taskRow.hovered ? theme.alpha(theme.text, 0.55) : theme.alpha(theme.text, 0.26)
                                                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: taskRow.task.done ? "✓" : ""
                                                    font.pixelSize: 10
                                                    color: theme.background
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: { dash.store.toggleTask(taskRow.task.id); taskCheckBounce.start(); }
                                            }
                                            Accessible.name: taskRow.task.done ? "Reopen task" : "Complete task"
                                            NumberAnimation {
                                                id: taskCheckBounce; target: taskCheck; property: "scale"
                                                from: 0.84; to: 1; duration: Style.duration(190); easing.type: Easing.OutBack
                                            }
                                        }
                                        TextField {
                                            id: taskTitleField
                                            visible: dash.editingTaskId === taskRow.task.id
                                            Layout.fillWidth: true; text: dash.taskDraft
                                            onTextChanged: if (visible) dash.taskDraft = text
                                            onAccepted: { dash.commitTask(); page.forceActiveFocus(); }
                                            Keys.onEscapePressed: dash.editingTaskId = ""
                                            color: theme.text; font.family: theme.font; font.pixelSize: 14
                                            padding: 1; background: null
                                            selectionColor: theme.accent; selectedTextColor: theme.background
                                        }
                                        Label {
                                            visible: dash.editingTaskId !== taskRow.task.id
                                            Layout.fillWidth: true; text: taskRow.task.title || ""
                                            maximumLineCount: 1; elide: Text.ElideRight
                                            font.pixelSize: 14
                                            color: taskRow.task.done ? theme.muted : theme.text
                                            font.strikeout: !!taskRow.task.done
                                            MouseArea {
                                                anchors.fill: parent; hoverEnabled: true
                                                onClicked: dash.selectedTaskId = taskRow.task.id
                                                onDoubleClicked: {
                                                    dash.editTask(taskRow.task);
                                                    Qt.callLater(function() { taskTitleField.forceActiveFocus(); taskTitleField.selectAll(); });
                                                }
                                            }
                                        }
                                        TextField {
                                            id: dueField
                                            visible: dash.dueTaskId === taskRow.task.id
                                            Layout.preferredWidth: 118; text: dash.dueDraft; font.pixelSize: 11
                                            placeholderText: "Due — try “tomorrow”"
                                            placeholderTextColor: theme.alpha(theme.text, 0.4)
                                            onTextChanged: if (visible) dash.dueDraft = text
                                            onAccepted: { dash.commitDue(); page.forceActiveFocus(); }
                                            Keys.onEscapePressed: dash.dueTaskId = ""
                                            color: theme.text; font.family: theme.font; padding: 2
                                            background: Rectangle {
                                                radius: 4
                                                color: theme.alpha(theme.text, 0.06)
                                                border.width: 1
                                                border.color: theme.alpha(theme.text, 0.16)
                                            }
                                        }
                                        Label {
                                            Layout.preferredWidth: 76
                                            horizontalAlignment: Text.AlignRight
                                            visible: dash.dueTaskId !== taskRow.task.id
                                            text: Dates.dueLabel(taskRow.task.due, dash.store.today)
                                            font.pixelSize: 11; elide: Text.ElideLeft
                                            color: (!taskRow.task.done && taskRow.task.due && taskRow.task.due < dash.store.today) ? theme.urgent : theme.muted
                                            MouseArea {
                                                anchors.fill: parent; hoverEnabled: true
                                                enabled: !taskRow.task.done
                                                onClicked: dash.selectedTaskId = taskRow.task.id
                                                onDoubleClicked: {
                                                    dash.editDue(taskRow.task);
                                                    Qt.callLater(function() { dueField.forceActiveFocus(); dueField.selectAll(); });
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.preferredWidth: 56; Layout.alignment: Qt.AlignVCenter
                                            spacing: 0; opacity: taskRow.hovered ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
                                            IconButton {
                                                iconName: "play"; iconSize: 14
                                                label: "Focus on task"
                                                onClicked: dash.store.chooseFocus(taskRow.task.title, 1500)
                                                ToolTip.visible: hovered; ToolTip.text: "Focus"
                                            }
                                            IconButton {
                                                iconName: dash.taskView === "Archive" ? "undo" : "archive"
                                                iconSize: 14
                                                label: dash.taskView === "Archive" ? "Restore task" : "Archive task"
                                                onClicked: {
                                                    if (dash.taskView === "Archive") dash.store.restoreTask(taskRow.task.id);
                                                    else { dash.store.archiveTask(taskRow.task.id); Qt.callLater(dash.selectFirstTask); }
                                                }
                                                ToolTip.visible: hovered; ToolTip.text: dash.taskView === "Archive" ? "Restore" : "Archive"
                                            }
                                        }
                                    }
                                }
                                Label {
                                    anchors.centerIn: parent; width: parent.width; visible: parent.count === 0
                                    text: dash.taskTag ? "No tasks tagged #" + dash.taskTag + " in this view." : dash.taskView === "Archive" ? "Archive is empty." : dash.taskView === "Completed" ? "No completed tasks yet." : "Nothing here.\nAdd a task below."
                                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; opacity: 0.65; lineHeight: 1.5
                                }
                            }
                            Item {
                                visible: dash.taskView === "Tags"
                                anchors.fill: parent
                                Flow {
                                    id: tagFlow
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    spacing: 10
                                Repeater {
                                    model: dash.tagCloud
                                    Rectangle {
                                        id: cloudChip
                                        required property var modelData
                                        readonly property int cloudSize: dash.tagSize(modelData.count)
                                        readonly property bool highlighted: cloudHover.containsMouse || dash.taskTag === modelData.tag
                                        implicitWidth: cloudRow.implicitWidth + 26
                                        implicitHeight: cloudSize + 18
                                        radius: 6
                                        color: cloudChip.highlighted ? theme.alpha(theme.accent, 0.12) : theme.alpha(theme.text, 0.04)
                                        border.width: 1
                                        border.color: cloudChip.highlighted ? theme.alpha(theme.accent, 0.45) : theme.alpha(theme.text, 0.10)
                                        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                                        Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                        RowLayout {
                                            id: cloudRow
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Label {
                                                Layout.alignment: Qt.AlignBaseline
                                                text: "#" + cloudChip.modelData.tag
                                                font.pixelSize: cloudChip.cloudSize
                                                font.weight: Font.DemiBold
                                                color: theme.alpha(theme.text, 0.85)
                                            }
                                            Label {
                                                Layout.alignment: Qt.AlignBaseline
                                                text: cloudChip.modelData.count
                                                font.pixelSize: 11
                                                color: theme.alpha(theme.text, 0.45)
                                            }
                                        }
                                        MouseArea {
                                            id: cloudHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: dash.openTag(cloudChip.modelData.tag)
                                        }
                                    }
                                }
                                    }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            visible: dash.taskView !== "Tags"
                            implicitHeight: 78; radius: 8
                            color: theme.alpha(theme.text, 0.03)
                            border.width: 1
                            border.color: theme.alpha(theme.text, 0.10)
                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 0
                                Entry {
                                    id: taskInput; Layout.fillWidth: true; maximumLength: 500
                                    implicitHeight: 30; padding: 1; background: null
                                    placeholderText: "＋  Add a task — try “tomorrow”"; onAccepted: dash.submitTask()
                                }
                                Entry {
                                    id: dueInput; Layout.fillWidth: true; maximumLength: 40
                                    implicitHeight: 26; padding: 1; background: null; font.pixelSize: 12
                                    placeholderText: "Due date (optional) · Enter to add"; onAccepted: dash.submitTask()
                                }
                            }
                        }
                    }
                    // The right pane leads with the whole task, not a summary:
                    // full title, full metadata, then the full body. The list
                    // stays single-line so the two sides have different jobs.
                    Item {
                        id: taskDetail
                        visible: dash.focusedCard === "tasks"
                        anchors.left: paneDivider.right; anchors.right: parent.right
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 32; spacing: 0
                            Label {
                                Layout.fillWidth: true; Layout.maximumWidth: 760
                                text: dash.selectedTask ? dash.selectedTask.title : dash.taskView === "Tags" ? "Browse by theme" : "Select a task"
                                font.pixelSize: 24; font.weight: Font.Medium; lineHeight: 1.2
                                wrapMode: Text.Wrap
                                color: dash.selectedTask && dash.selectedTask.done ? theme.muted : theme.text
                            }
                            Item {
                                Layout.fillWidth: true; Layout.maximumWidth: 760
                                Layout.topMargin: 14
                                implicitHeight: metaRow.implicitHeight
                                visible: !!dash.selectedTask
                                Row {
                                    id: metaRow
                                    spacing: 10
                                    Label {
                                        text: Dates.dueLabel(dash.selectedTask ? dash.selectedTask.due : "", dash.store.today) || "No due date"
                                        font.pixelSize: 12
                                        color: dash.selectedTask && dash.selectedTask.due && !dash.selectedTask.done && dash.selectedTask.due < dash.store.today ? theme.urgent : theme.alpha(theme.text, 0.62)
                                    }
                                    Label {
                                        visible: !!dash.selectedTask && !!dash.selectedTask.createdAt
                                        text: "·"; font.pixelSize: 11; color: theme.alpha(theme.text, 0.28)
                                    }
                                    Label {
                                        visible: !!dash.selectedTask && !!dash.selectedTask.createdAt
                                        text: dash.selectedTask && dash.selectedTask.createdAt ? "Added " + Qt.formatDate(new Date(dash.selectedTask.createdAt), "d MMM") : ""
                                        font.pixelSize: 12; color: theme.alpha(theme.text, 0.50)
                                    }
                                    Label {
                                        visible: !!dash.selectedTask && (dash.selectedTask.tags || []).length > 0
                                        text: "·"; font.pixelSize: 11; color: theme.alpha(theme.text, 0.28)
                                    }
                                    Repeater {
                                        model: dash.selectedTask ? (dash.selectedTask.tags || []) : []
                                        Item {
                                            required property var modelData
                                            implicitWidth: tagLabel.implicitWidth
                                            implicitHeight: tagLabel.implicitHeight
                                            Label {
                                                id: tagLabel
                                                text: "#" + modelData
                                                font.pixelSize: 12
                                                font.underline: tagMouse.containsMouse
                                                font.weight: dash.taskTag === modelData ? Font.DemiBold : Font.Normal
                                                color: dash.taskTag === modelData ? theme.text : tagMouse.containsMouse ? theme.text : theme.alpha(theme.text, 0.62)
                                            }
                                            MouseArea {
                                                id: tagMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: dash.toggleTag(modelData)
                                            }
                                        }
                                    }
                                }
                            }
                            Flickable {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                Layout.maximumWidth: 760; Layout.topMargin: 22
                                clip: true; boundsBehavior: Flickable.StopAtBounds
                                contentWidth: width
                                contentHeight: detailBody.implicitHeight
                                Column {
                                    id: detailBody
                                    width: parent.width
                                    spacing: 26
                                    Label {
                                        width: parent.width
                                        text: dash.selectedTask && dash.selectedTask.body
                                            ? dash.selectedTask.body
                                            : dash.taskView === "Tags"
                                                ? "Tags link tasks, notes and daily entries. Pick one to filter the list."
                                                : "No notes on this task."
                                        color: dash.selectedTask && dash.selectedTask.body ? theme.alpha(theme.text, 0.80) : theme.alpha(theme.text, 0.35)
                                        wrapMode: Text.Wrap; font.pixelSize: 14; lineHeight: 1.65
                                    }
                                    Column {
                                        width: parent.width
                                        spacing: 2
                                        visible: dash.graphRelated.length > 0
                                        Label {
                                            text: "CONNECTED"
                                            font.pixelSize: 10; font.letterSpacing: 1.4; font.weight: Font.DemiBold
                                            color: theme.alpha(theme.text, 0.4)
                                            bottomPadding: 6
                                        }
                                        Repeater {
                                            model: dash.graphRelated
                                            Rectangle {
                                                id: relatedRow
                                                required property var modelData
                                                width: detailBody.width; height: 34
                                                radius: 4
                                                color: relatedMouse.containsMouse ? theme.alpha(theme.text, 0.045) : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6; anchors.rightMargin: 8
                                                    spacing: 9
                                                    Icon {
                                                        name: relatedRow.modelData.kind === "task" ? "link" : "file-text"
                                                        size: 13
                                                        tint: theme.alpha(theme.text, 0.5)
                                                    }
                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: relatedRow.modelData.title
                                                        elide: Text.ElideRight; maximumLineCount: 1
                                                        font.pixelSize: 13
                                                        color: theme.alpha(theme.text, 0.75)
                                                    }
                                                    Label {
                                                        text: relatedRow.modelData.direction === "in" ? "linked here" : relatedRow.modelData.relation
                                                        font.pixelSize: 10; font.letterSpacing: 0.6
                                                        color: theme.alpha(theme.text, 0.38)
                                                    }
                                                }
                                                MouseArea {
                                                    id: relatedMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: dash.openRelated(relatedRow.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: false
                                spacing: 6
                                visible: !!dash.selectedTask
                                ActionButton {
                                    icon: "play"; text: "Focus 25m"
                                    onClicked: {
                                        dash.store.chooseFocus(dash.selectedTask.title, 1500);
                                        dash.focusedCard = "focus";
                                    }
                                }
                                ActionButton {
                                    icon: "pencil"; text: "Edit"
                                    onClicked: dash.editTask(dash.selectedTask)
                                }
                                IconButton {
                                    iconName: dash.selectedTask && dash.selectedTask.archived ? "undo" : "archive"
                                    label: "Archive selected task"
                                    onClicked: {
                                        if (!dash.selectedTask) return;
                                        if (dash.selectedTask.archived) dash.store.restoreTask(dash.selectedTask.id);
                                        else { dash.store.archiveTask(dash.selectedTask.id); Qt.callLater(dash.selectFirstTask); }
                                    }
                                    ToolTip.visible: hovered; ToolTip.text: dash.selectedTask && dash.selectedTask.archived ? "Restore" : "Archive"
                                }
                            }
                        }
                    }
                    }
                }
                Card {
                    role: "focus"
                    color: theme.focus
                    x: workspaceGrid.sx("focus"); y: workspaceGrid.sy("focus")
                    width: workspaceGrid.sw("focus"); height: workspaceGrid.sh("focus")
                    z: dash.focusedCard === "focus" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "focus"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 30; spacing: 10
                        CardHeading { Layout.fillWidth: true; icon: "play"; text: "Focus" }
                        Label { Layout.fillWidth: true; text: dash.store.focusState.title; wrapMode: Text.Wrap; maximumLineCount: 2; font.pixelSize: 16; opacity: 0.75 }
                        Dial {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.minimumHeight: 160; Layout.preferredHeight: 190
                            progress: dash.store.focusState.duration > 0 ? dash.store.focusState.elapsed / dash.store.focusState.duration : (dash.store.focusState.running ? 0.999 : 0)
                            time: dash.store.timerText
                            hint: dash.store.focusState.running ? "tap to pause" : "tap to start"
                            onToggled: dash.store.toggleTimer()
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 8
                            Tab { text: "25m"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 1500) }
                            Tab { text: "50m"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 3000) }
                            Tab { text: "∞"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 0) }
                            Tab { text: "+5m"; enabled: dash.store.focusState.duration > 0; onClicked: dash.store.addFive() }
                        }
                        Entry {
                            id: minutesInput; Layout.fillWidth: true; implicitHeight: 34
                            placeholderText: "Custom minutes · Enter"; maximumLength: 3
                            validator: IntValidator { bottom: 1; top: 999 }
                            onAccepted: if (acceptableInput) { dash.store.chooseFocus(dash.store.focusState.title, Number(text) * 60); page.forceActiveFocus(); }
                        }
                        Label { Layout.alignment: Qt.AlignHCenter; text: dash.store.todayMinutes + " minutes focused today"; font.pixelSize: 12; opacity: 0.65 }
                    }
                }
                Card {
                    role: "notes"; volume: Visual.volume(dash.dayNotes.length)
                    color: theme.notes
                    x: workspaceGrid.sx("notes"); y: workspaceGrid.sy("notes")
                    width: workspaceGrid.sw("notes"); height: workspaceGrid.sh("notes")
                    z: dash.focusedCard === "notes" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "notes"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24
                        anchors.topMargin: dash.focusedCard === "notes" ? 10 : 32
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true; Layout.rightMargin: dash.focusedCard === "notes" ? 30 : 0
                            spacing: 10
                            CardHeading { Layout.fillWidth: true; icon: "notebook-pen"; text: "Notepad" }
                            NewNoteButton { onClicked: dash.createNoteForDay(dash.store.today) }
                        }
                        RowLayout {
                            visible: dash.focusedCard === "notes" && dash.notesView !== "board"
                            Layout.fillWidth: true; spacing: 8
                            Tab { text: "‹ Board"; onClicked: dash.returnToBoard() }
                            Item { Layout.fillWidth: true }
                            DayArrow { iconName: "chevron-left"; Accessible.name: "Previous note"; enabled: dash.openNoteIndex > 0; onClicked: dash.browseNote(-1) }
                            Label {
                                text: dash.openNoteId ? Notes.boardDate(Notes.isDaily(dash.openNoteId) ? dash.store.noteDay : (dash.openNote ? dash.openNote.date : ""), dash.store.today) : "New note"
                                font.pixelSize: 12; color: theme.muted
                            }
                            DayArrow { iconName: "chevron-right"; Accessible.name: "Next note"; enabled: dash.openNoteIndex >= 0 && dash.openNoteIndex < dash.allNotes.length - 1; onClicked: dash.browseNote(1) }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: dash.notesView === "write" && dash.focusedCard !== "notes"
                            DayArrow { iconName: "chevron-left"; Accessible.name: "Previous day"; onClicked: dash.store.moveNoteDay(-1) }
                            Label {
                                text: Notes.boardDate(dash.store.noteDay, dash.store.today)
                                font.pixelSize: 13; color: theme.alpha(theme.text, 0.8)
                            }
                            DayArrow { iconName: "chevron-right"; Accessible.name: "Next day"; enabled: dash.store.noteDay < dash.store.today; onClicked: dash.store.moveNoteDay(1) }
                            Tab { text: "Today"; visible: dash.store.noteDay !== dash.store.today; onClicked: dash.store.noteDay = dash.store.today }
                            Item { Layout.fillWidth: true }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.alpha(theme.text, 0.14); visible: dash.notesView === "write" }
                        ScrollView {
                            visible: dash.notesView === "write"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            TextArea {
                                id: notes; text: dash.store.note
                                onTextChanged: if (activeFocus) dash.store.setNote(text)
                                placeholderText: "Catch a thought.\nMake a little space."; placeholderTextColor: theme.muted
                                color: dash.textColor; wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 16
                                padding: 0; background: null; selectionColor: theme.accent; selectedTextColor: theme.background
                                Keys.onPressed: function(event) {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        var start = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                                        var end = text.indexOf("\n", cursorPosition); if (end < 0) end = text.length;
                                        dash.store.addTask(text.slice(start,end)); event.accepted = true;
                                    }
                                }
                            }
                        }
                        // Notes dated today stay as compact pills: a link, not a
                        // second list competing with the editor.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: dash.notesView === "write" && dash.dayNotes.length > 0
                            Repeater {
                                model: dash.dayNotes
                                Rectangle {
                                    id: notePill
                                    required property var modelData
                                    implicitHeight: 26
                                    implicitWidth: Math.min(notePillRow.implicitWidth + 16, 320)
                                    radius: 4
                                    color: pillHover.hovered ? theme.alpha(theme.accent, 0.16) : theme.alpha(theme.text, 0.05)
                                    border.width: 1
                                    border.color: pillHover.hovered ? theme.alpha(theme.accent, 0.45) : theme.alpha(theme.text, 0.10)
                                    RowLayout {
                                        id: notePillRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 8; anchors.rightMargin: 8
                                        spacing: 6
                                        Icon { name: "file-text"; size: 12; tint: theme.alpha(theme.text, 0.55) }
                                        Label {
                                            Layout.fillWidth: true
                                             text: notePill.modelData.title
                                             textFormat: Text.PlainText
                                            elide: Text.ElideRight; maximumLineCount: 1
                                            font.pixelSize: 11
                                            color: theme.alpha(theme.text, 0.82)
                                        }
                                    }
                                    HoverHandler { id: pillHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: dash.viewNote(notePill.modelData.id)
                                    }
                                }
                            }
                        }
                        Label {
                            visible: dash.notesView === "write"
                            text: (notes.text.trim() ? notes.text.trim().split(/\s+/).length : 0) + " words · Ctrl+Enter → task"
                            font.pixelSize: 11; color: theme.alpha(theme.text, 0.5)
                        }
                        Loader {
                            id: notesLoader
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: dash.notesView === "edit"
                            active: dash.notesLoaded
                            sourceComponent: Component {
                                NotesPane {
                                    store: dash.store; embedded: true
                                    onFinished: dash.showNotes("board")
                                }
                            }
                            onLoaded: if (dash.pendingNoteDay) {
                                var pane = notesLoader.item as NotesPane;
                                if (pane) { pane.createForDay(dash.pendingNoteDay); dash.pendingNoteDay = ""; }
                            }
                        }
                        GridView {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.topMargin: dash.notesView === "board" ? 10 : 0
                            visible: dash.focusedCard === "notes" && dash.notesView === "board"
                            clip: true
                            model: dash.allNotes
                            readonly property int columns: Math.max(1, Math.min(4, Math.floor(width / 300)))
                            cellWidth: Math.max(220, Math.floor(width / columns))
                            cellHeight: 190
                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded; width: 4
                                background: null
                                contentItem: Rectangle { implicitWidth: 4; radius: 2; color: theme.alpha(theme.text, 0.28) }
                            }
                            delegate: Rectangle {
                                id: noteCard
                                required property var modelData
                                width: GridView.view.cellWidth - 12
                                height: 178
                                radius: 6
                                color: noteHover.hovered ? theme.hover : theme.raised
                                border.width: 1
                                border.color: theme.alpha(theme.text, noteHover.hovered ? 0.14 : 0.05)
                                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 8
                                    RowLayout {
                                        spacing: 6
                                        Icon { name: "file-text"; size: 12; tint: theme.alpha(theme.text, 0.55) }
                                        Label {
                                            Layout.fillWidth: true
                                        text: Notes.boardDate(noteCard.modelData.date, dash.store.today)
                                            font.pixelSize: 11; color: theme.alpha(theme.text, 0.6)
                                        }
                                        Label {
                                            visible: !!noteCard.modelData.pinned
                                            text: "PINNED"; font.pixelSize: 9; font.letterSpacing: 1
                                            color: theme.accent
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                         text: noteCard.modelData.title
                                         textFormat: Text.PlainText
                                        font.pixelSize: 15; font.weight: Font.DemiBold
                                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                    }
                                    Label {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                         text: Notes.excerpt(Notes.plain(noteCard.modelData.body), 300) || "No text yet."
                                         textFormat: Text.PlainText
                                        wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight
                                        font.pixelSize: 12; lineHeight: 1.45
                                        color: noteCard.modelData.body ? theme.alpha(theme.text, 0.7) : theme.alpha(theme.text, 0.35)
                                    }
                                }
                                HoverHandler { id: noteHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: dash.viewNote(noteCard.modelData.id)
                                }
                            }
                            Label {
                                anchors.centerIn: parent; width: parent.width
                                visible: parent.count === 0
                                text: "No notes yet."
                                horizontalAlignment: Text.AlignHCenter
                                color: theme.alpha(theme.text, 0.4); font.pixelSize: 12
                            }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: dash.focusedCard === "notes" && dash.notesView === "note"
                            ColumnLayout {
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width, 900)
                                spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true
                                    Tab { text: "‹ Board"; onClicked: dash.showNotes("board") }
                                    Item { Layout.fillWidth: true }
                                    Tab {
                                        text: "Edit"
                                        onClicked: {
                                            if (!dash.openNote) return;
                                            dash.notesLoaded = true;
                                            dash.notesView = "edit";
                                            Qt.callLater(function() {
                                                var pane = notesLoader.item as NotesPane;
                                                if (pane) pane.select(dash.openNote);
                                            });
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                     text: dash.openNote ? dash.openNote.title : ""
                                     textFormat: Text.PlainText
                                    font.pixelSize: 24; font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                }
                                RowLayout {
                                    spacing: 10
                                    Label {
                                        text: dash.openNote ? dash.noteDate(dash.openNote) : ""
                                        font.pixelSize: 12; color: theme.alpha(theme.text, 0.55)
                                    }
                                    Repeater {
                                        model: dash.openNote ? (dash.openNote.tags || []) : []
                                        Label {
                                            required property var modelData
                                            text: "#" + modelData
                                            font.pixelSize: 11; color: theme.alpha(theme.text, 0.6)
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        visible: !!dash.openNote && !!dash.openNote.pinned
                                        text: "PINNED"; font.pixelSize: 9; font.letterSpacing: 1
                                        color: theme.accent
                                    }
                                }
                                ScrollView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                    Column {
                                        width: parent.width
                                        spacing: 10
                                        Repeater {
                                            model: Notes.readingLines(dash.openNote ? dash.openNote.body : "")
                                            Flow {
                                                id: readingLine
                                                required property var modelData
                                                width: parent.width
                                                spacing: 5
                                                Repeater {
                                                    model: modelData.parts
                                                    delegate: Item {
                                                        id: token
                                                        required property var modelData
                                                        readonly property bool reference: modelData.reference !== undefined
                                                        width: reference ? refPill.implicitWidth : plainText.implicitWidth
                                                        height: Math.max(refPill.implicitHeight, plainText.implicitHeight)
                                                        Label {
                                                            id: plainText
                                                            visible: !token.reference
                                                            text: token.modelData.text || ""
                                                            textFormat: Text.PlainText
                                                            font.pixelSize: 15
                                                            font.weight: readingLine.modelData.heading ? Font.DemiBold : Font.Normal
                                                            color: theme.text
                                                        }
                                                        Rectangle {
                                                            id: refPill
                                                            visible: token.reference
                                                            implicitWidth: Math.min(refLabel.implicitWidth + 20, 360)
                                                            implicitHeight: 28
                                                            radius: 5
                                                            color: theme.alpha(theme.accent, 0.18)
                                                            Label {
                                                                id: refLabel
                                                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                                                             text: token.modelData.reference || ""
                                                             textFormat: Text.PlainText
                                                                elide: Text.ElideRight
                                                                verticalAlignment: Text.AlignVCenter
                                                                color: theme.text; font.pixelSize: 13; font.weight: Font.DemiBold
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: dash.openWikiLink(token.modelData.reference)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Card {
                    role: "events"; volume: Visual.volume(dash.calendarDay ? dash.calendarDay.events.length : 0)
                    color: theme.events
                    x: workspaceGrid.sx("events"); y: workspaceGrid.sy("events")
                    width: workspaceGrid.sw("events"); height: workspaceGrid.sh("events")
                    z: dash.focusedCard === "events" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "events"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 16
                        CardHeading { Layout.fillWidth: true; icon: "calendar"; text: "Events" }
                        RowLayout {
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 3
                                Label { Layout.fillWidth: true; visible: !!dash.calendarDay; text: dash.calendarDay ? Qt.formatDate(new Date(dash.calendarDay.date + "T12:00:00"), "dddd") : ""; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Label { Layout.fillWidth: true; text: dash.calendarDay ? dash.calendarDay.label : "Calendar"; font.pixelSize: 13 }
                            }
                            Glyph { objectName: "dashboard-previous"; text: "‹"; enabled: dash.calendarIndex > 0; onClicked: dash.moveDay(-1) }
                            Glyph { objectName: "dashboard-next"; text: "›"; enabled: dash.calendarIndex < dash.store.agendaDays.length - 1; onClicked: dash.moveDay(1) }
                        }
                        Tab { text: "Today"; visible: dash.calendarDate !== dash.store.calendarToday; onClicked: dash.calendarDate = dash.store.calendarToday }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6
                            Entry { id: eventTitle; Layout.fillWidth: true; maximumLength: 256; placeholderText: "＋  Add an event"; onAccepted: dash.submitEvent() }
                            Entry { id: eventStart; Layout.fillWidth: true; maximumLength: 32; placeholderText: "Starts (optional) · Enter to add"; onAccepted: dash.submitEvent() }
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 14
                            model: dash.calendarDay ? dash.calendarDay.events : []
                            ScrollBar.vertical: ScrollBar {}
                            delegate: AbstractButton {
                                id: eventLink
                                objectName: "event-open"
                                required property var modelData
                                width: ListView.view.width; height: 102; padding: 13
                                hoverEnabled: true
                                Accessible.name: "Open calendar: " + (modelData.title || "Untitled event")
                                onClicked: dash.store.openCalendar(dash.calendarDate)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                ToolTip.visible: hovered; ToolTip.text: "Open full calendar"
                                background: Rectangle { radius: 3; color: eventLink.hovered ? theme.hover : theme.raised }
                                contentItem: ColumnLayout {
                                    spacing: 7
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.title || "Untitled event"; font.weight: Font.Medium; font.pixelSize: 16; wrapMode: Text.Wrap; maximumLineCount: 2 }
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.all_day ? "All day" : dash.eventClock(eventLink.modelData.start_ms) + " – " + dash.eventClock(eventLink.modelData.end_ms); font.pixelSize: 12; opacity: 0.7 }
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.calendar || ""; font.pixelSize: 11; opacity: 0.55 }
                                }
                                Glyph {
                                    anchors.right: parent.right; anchors.top: parent.top; z: 2
                                    text: "⊟"; visible: !!eventLink.modelData.localId
                                    onClicked: dash.store.archiveEvent(eventLink.modelData.localId)
                                    Accessible.name: "Archive event"
                                    ToolTip.visible: hovered; ToolTip.text: "Archive event"
                                }
                            }
                            Column {
                                anchors.centerIn: parent; width: parent.width; spacing: 12; visible: parent.count === 0
                                Label { width: parent.width; text: "Nothing scheduled"; font.pixelSize: 21; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter }
                                Label { width: parent.width; text: dash.store.agendaDays.length ? "Pick another day with the arrows above." : dash.store.calendarSource === "off" ? "Calendar is off. Choose a source in Connections." : dash.store.calendarSource === "google" ? "Connect Google Calendar in Connections to see events here." : dash.store.calendarSource === "caldav" ? "Connect your CalDAV calendar in Connections, or add an event above." : "Connect your calendars in OmaCal to see events here."; font.pixelSize: 14; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; opacity: 0.65 }
                            }
                        }
                        Label { visible: dash.store.calendarSource === "google" && !!dash.store.googleCalendar.lastError; text: dash.store.googleCalendar.lastError; Layout.fillWidth: true; wrapMode: Text.Wrap; color: theme.urgent; font.pixelSize: 12 }
                        Label { Layout.fillWidth: true; text: dash.store.calendarName + " · " + dash.store.agendaDays.length + " days available"; font.pixelSize: 12; opacity: 0.65 }
                    }
                }
                Card {
                    role: "mail"; volume: Visual.volume(dash.store.newMail.length)
                    attention: dash.store.newMail.length ? 1 : 0
                    color: theme.mail
                    x: workspaceGrid.sx("mail"); y: workspaceGrid.sy("mail")
                    width: workspaceGrid.sw("mail"); height: workspaceGrid.sh("mail")
                    z: dash.focusedCard === "mail" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "mail"
                    Loader {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35
                        active: dash.mailLoaded; asynchronous: true
                        sourceComponent: Component { HeyMail { store: dash.store } }
                    }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 8
                        visible: !dash.mailLoaded
                        CardHeading { Layout.fillWidth: true; icon: "mail"; text: "Mail" }
                        Label { Layout.fillWidth: true; text: dash.store.newMail.length + " unread · " + dash.store.mailName; font.pixelSize: 12; opacity: 0.7 }
                        Repeater {
                            model: dash.store.newMail.slice(0, 3)
                            Label {
                                required property var modelData
                                Layout.fillWidth: true; text: modelData.creator || modelData.title || "Message"
                                font.pixelSize: 13; opacity: 0.8; elide: Text.ElideRight
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Label { text: "Expand to read"; font.pixelSize: 12; color: theme.accent }
                    }
                }
            }
            // Heavy panes are created on first use and then hidden when closed.
            // They never block the initial workspace paint.
            Loader {
                id: connectionsLoader
                Layout.fillWidth: true; Layout.fillHeight: true
                active: dash.connectionsLoaded; asynchronous: true
                visible: dash.connectionsOpen
                opacity: dash.connectionsOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
                sourceComponent: Component { ConnectionsPane { store: dash.store } }
            }
            Rectangle {
                id: insightsPane
                visible: dash.insights && !dash.connectionsOpen; Layout.fillWidth: true; Layout.fillHeight: true; color: theme.focus; radius: 4
                onVisibleChanged: if (visible) { opacity = 0; insightsReveal.start(); }
                NumberAnimation { id: insightsReveal; target: insightsPane; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 48; spacing: 24
                    Label { text: "The work you put in"; font.pixelSize: 34; font.weight: Font.DemiBold }
                    Label { text: dash.store.todayMinutes + " minutes of focus today     ·     " + dash.store.todayCompleted + " tasks completed here today"; font.pixelSize: 21 }
                    RowLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 25
                        Repeater {
                            model: dash.store.week
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 15
                                Item { Layout.fillHeight: true }
                                Label { Layout.alignment: Qt.AlignHCenter; text: modelData.minutes + "m"; font.pixelSize: 23 }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 10 + 250 * modelData.minutes / Math.max(1, ...dash.store.week.map(d => d.minutes)); radius: 12; color: theme.accent; opacity: modelData.minutes ? 0.8 : 0.15 }
                                Label { Layout.alignment: Qt.AlignHCenter; text: modelData.label; font.pixelSize: 17 }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Label { Layout.fillWidth: true; text: dash.store.notice || "Your day, a little closer."; color: theme.muted; font.pixelSize: 13 }
                Label { text: dash.compact ? "Hover to open · Pin to keep open" : "Esc to return to the workspace"; color: theme.muted; font.pixelSize: 13 }
            }
        }
    }
}
