pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Logic.js" as Logic
import "Dates.js" as Dates
import "Visual.js" as Visual

PanelWindow {
    id: dash
    Theme { id: theme }
    required property var store
    signal dismissed()
    signal expandRequested()
    property bool compact: false
    property bool pinned: false
    property bool awaitingEntry: false
    readonly property bool hovered: workspaceHover.hovered
    readonly property bool editing: taskInput.activeFocus || dueInput.activeFocus || notes.activeFocus || minutesInput.activeFocus || eventTitle.activeFocus || eventStart.activeFocus || connectionsOpen || notesOpen
    readonly property real uiScale: compact ? 0.82 : 1
    property string taskView: "Today"
    property bool insights: false
    property bool notesOpen: false
    property bool notesLoaded: false
    onNotesOpenChanged: if (notesOpen) { connectionsOpen=false; insights=false; notesLoaded=true; }
    property bool connectionsOpen: false
    property bool connectionsLoaded: false
    onConnectionsOpenChanged: if (connectionsOpen) { notesOpen=false; insights=false; connectionsLoaded=true; }
    property bool mailLoaded: false
    onInsightsChanged: if (insights) { notesOpen=false; connectionsOpen=false; }
    // UI-local memory only: a quiet bookmark on the last view you opened.
    // It resets when the shell restarts and never writes to the workspace.
    property string lastCard: "tasks"
    // Empty means the five-card grid. A role means that card has expanded to
    // the full workspace; no separate collapsed window exists.
    property string focusedCard: ""
    property bool frosted: true
    property bool frostReady: false
    readonly property int taskAttention: Visual.attention(dash.store.tasks, dash.store.today, 0).level
    readonly property var dayNotes: {
        store.revision;
        return store.notesForDay(store.noteDay);
    }
    property string calendarDate: store.calendarToday
    readonly property int calendarIndex: store.agendaDays.findIndex(d => d.date === dash.calendarDate)
    readonly property var calendarDay: store.agendaDays[Math.max(0, calendarIndex)] || null
    readonly property var taskRows: Logic.tasksInView(dash.store.tasks, dash.taskView, dash.store.today)
    readonly property var selectedTask: dash.store.tasks.find(t => t.id === dash.selectedTaskId) || null
    property string selectedTaskId: ""
    property string editingTaskId: ""
    property string dueTaskId: ""
    property string taskDraft: ""
    property string dueDraft: ""
    function taskCount(view) { return Logic.tasksInView(dash.store.tasks, view, dash.store.today).length }
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
    // Status is the rail's eyebrow. It states where the task sits without
    // repeating the due date that already sits in the metadata line.
    function taskStatus(task) {
        if (!task) return "";
        if (task.archived) return "ARCHIVED";
        if (task.done) return "DONE";
        if (!Dates.validDay(task.due)) return "NO DATE";
        if (task.due < dash.store.today) return "OVERDUE";
        if (task.due === dash.store.today) return "TODAY";
        return "UPCOMING";
    }
    function selectFirstTask() {
        dash.selectedTaskId = dash.taskRows.length ? dash.taskRows[0].id : "";
    }
    onTaskViewChanged: Qt.callLater(selectFirstTask)
    onFocusedCardChanged: {
        if (focusedCard === "mail") mailLoaded = true;
        if (focusedCard === "tasks" && !selectedTaskId && taskRows.length) selectedTaskId = taskRows[0].id;
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
    WlrLayershell.keyboardFocus: visible ? (compact ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
    color: "transparent"
    onVisibleChanged: {
        if (!visible) { frostReady = false; frostLoader.active = false; focusedCard = ""; editingTaskId = ""; dueTaskId = ""; return; }
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
                    blurEnabled: true; blur: 0.9; blurMax: 48; blurMultiplier: 1
                }
                Rectangle { anchors.fill: parent; color: theme.background; opacity: 0.18 }
            }
        }
    }
    Rectangle {
        anchors.fill: parent; z: 1
        color: dash.frosted && dash.frostReady ? theme.alpha(theme.background, 0.66) : theme.background
        radius: 0
        Behavior on color { ColorAnimation { duration: Style.duration(160) } }
    }
    function close() { store.flush(); dismissed(); }
    function moveDay(offset) {
        var index = Math.max(0, calendarIndex) + offset;
        if (index >= 0 && index < store.agendaDays.length) calendarDate = store.agendaDays[index].date;
    }
    function eventClock(ms) { return store.calendarClocks[String(ms)] || Qt.formatTime(new Date(ms), "h:mm AP"); }
    Connections {
        target: dash.store
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
        property bool bookmarked: card.role && card.role === dash.lastCard
        property bool hovered: cardHover.hovered
        property real stackLift: card.hovered && !dash.focusedCard ? 3 : 0
        default property alias content: body.data
        opacity: dash.focusedCard && !card.focused ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }

        Repeater {
            model: 3
            Rectangle {
                required property int index
                visible: index < card.volume
                z: -1 - index
                x: (index + 1) * 5 + card.stackLift
                y: (index + 1) * 5 + card.stackLift
                width: card.width; height: card.height; radius: 6
                color: card.color
                opacity: index === 0 ? 0.5 : index === 1 ? 0.3 : 0.16
                Behavior on x { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
            }
        }
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
        Rectangle {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            anchors.leftMargin: 10; anchors.bottomMargin: 12; z: 3
            width: 3; height: 14; radius: 1.5
            color: theme.accent; opacity: 0.8
            visible: card.bookmarked
        }
        AbstractButton {
            id: expand
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10; z: 4
            width: 30; height: 30
            hoverEnabled: true; focusPolicy: Qt.NoFocus
            opacity: card.hovered || card.focused ? 1 : 0.32
            Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
            onClicked: dash.focusedCard = card.focused ? "" : card.role
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
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (dash.editingTaskId) { dash.editingTaskId = ""; event.accepted = true; return; }
                if (dash.dueTaskId) { dash.dueTaskId = ""; event.accepted = true; return; }
                if (dash.focusedCard) { dash.focusedCard = ""; event.accepted = true; }
                else dash.close();
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
        ColumnLayout {
            anchors.centerIn: parent
            width: (dash.compact ? parent.width - 30 : Math.min(2100, parent.width - 80)) / dash.uiScale
            height: (dash.compact ? parent.height - 30 : Math.min(980, parent.height - 100)) / dash.uiScale
            scale: dash.uiScale
            spacing: 25
            RowLayout {
                Layout.fillWidth: true
                Image { Layout.preferredWidth: 46; Layout.preferredHeight: 46; source: Qt.resolvedUrl("assets/saturn.svg"); fillMode: Image.PreserveAspectFit }
                ColumnLayout {
                    spacing: 3
                    Label { text: "Saturn"; color: theme.text; font.pixelSize: 27; font.weight: Font.DemiBold }
                    Label { text: "A little room for your day."; color: theme.muted; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                Tab { text: "Workspace"; selected: !dash.insights && !dash.connectionsOpen && !dash.notesOpen; onClicked: { dash.focusedCard = ""; dash.notesOpen = false; dash.insights = false; dash.connectionsOpen = false; dash.lastCard = "tasks"; } }
                Tab { text: "Notes"; selected: dash.notesOpen; onClicked: { dash.focusedCard = ""; store.notesSelection = ""; dash.notesOpen = true; dash.lastCard = "notes"; } }
                Tab { text: "Insights"; selected: dash.insights; onClicked: { dash.focusedCard = ""; dash.insights = true; dash.connectionsOpen = false; dash.lastCard = "insights"; } }
                Tab { text: "Connections"; selected: dash.connectionsOpen; onClicked: { dash.focusedCard = ""; dash.connectionsOpen = true; dash.insights = false; dash.lastCard = "connections"; } }
                Tab { text: dash.frosted ? "Frost" : "Frost off"; selected: dash.frosted; onClicked: dash.frosted = !dash.frosted; ToolTip.visible: hovered; ToolTip.text: "Blur the desktop behind the workspace" }
                Glyph { text: "×"; onClicked: dash.close(); Accessible.name: "Close workspace" }
            }
            Item {
                id: workspaceGrid
                visible: !dash.insights && !dash.connectionsOpen && !dash.notesOpen
                onVisibleChanged: if (visible) { opacity = 0; workspaceReveal.start(); }
                Layout.fillWidth: true; Layout.fillHeight: true
                readonly property var slots: Visual.grid(width, height)
                function sx(role) { return dash.focusedCard === role ? 0 : slots.cards[role].x }
                function sy(role) { return dash.focusedCard === role ? 0 : slots.cards[role].y }
                function sw(role) { return dash.focusedCard === role ? width : slots.cards[role].width }
                function sh(role) { return dash.focusedCard === role ? height : slots.cards[role].height }
                NumberAnimation { id: workspaceReveal; target: workspaceGrid; property: "opacity"; from: 0; to: 1; duration: Style.duration(180); easing.type: Easing.OutCubic }
                Card {
                    role: "tasks"; volume: Visual.volume(dash.taskRows.length); attention: dash.taskAttention
                    color: theme.tasks
                    x: workspaceGrid.sx("tasks"); y: workspaceGrid.sy("tasks")
                    width: workspaceGrid.sw("tasks"); height: workspaceGrid.sh("tasks")
                    z: dash.focusedCard === "tasks" ? 10 : 0
                    enabled: !dash.focusedCard || dash.focusedCard === "tasks"
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 12
                        RowLayout {
                            Label {
                                Layout.fillWidth: true; font.pixelSize: 22; font.weight: Font.DemiBold
                                text: ({Today: "Today’s tasks", Upcoming: "Upcoming", All: "All tasks", Completed: "Completed", Archive: "Archive"})[dash.taskView]
                            }
                            Label {
                                text: Qt.formatDate(new Date(dash.store.now), "ddd, d MMM") + " · " + dash.taskRows.length + (dash.taskView === "Completed" ? " done" : " to do")
                                font.pixelSize: 12; opacity: 0.7
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 14
                            Tab { text: "Today " + dash.taskCount("Today"); selected: dash.taskView === "Today"; onClicked: dash.taskView = "Today" }
                            Tab { text: "Upcoming " + dash.taskCount("Upcoming"); selected: dash.taskView === "Upcoming"; onClicked: dash.taskView = "Upcoming" }
                            Tab { text: "All " + dash.taskCount("All"); selected: dash.taskView === "All"; onClicked: dash.taskView = "All" }
                            Tab { text: "Done " + dash.taskCount("Completed"); selected: dash.taskView === "Completed"; onClicked: dash.taskView = "Completed" }
                            Tab { text: "Archive " + dash.taskCount("Archive"); selected: dash.taskView === "Archive"; onClicked: dash.taskView = "Archive" }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            ListView {
                                id: taskList
                                anchors.fill: parent
                                anchors.rightMargin: dash.focusedCard === "tasks" ? Math.round(parent.width * 0.40) + 20 : 0
                                clip: true; spacing: 2; topMargin: 4; bottomMargin: 4
                                model: dash.taskRows
                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded; width: 4
                                    background: null
                                    contentItem: Rectangle { implicitWidth: 4; radius: 2; color: theme.alpha(theme.text, 0.28) }
                                }
                                delegate: Item {
                                    id: taskRow
                                    required property var modelData
                                    property var task: modelData
                                    property bool hovered: taskHover.hovered
                                    property bool selected: dash.selectedTaskId === task.id
                                    width: ListView.view.width; height: 44
                                    HoverHandler { id: taskHover }
                                    Rectangle {
                                        anchors.fill: parent; radius: 4
                                        color: taskRow.selected ? theme.alpha(theme.text, 0.085) : taskRow.hovered ? theme.alpha(theme.text, 0.04) : "transparent"
                                        Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; acceptedButtons: Qt.LeftButton
                                        onClicked: dash.selectedTaskId = taskRow.task.id
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10; anchors.rightMargin: 6
                                        spacing: 10
                                        Item {
                                            id: taskCheck
                                            Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                            Rectangle {
                                                anchors.centerIn: parent; width: 18; height: 18; radius: 9
                                                color: taskRow.task.done ? theme.accent : "transparent"
                                                border.width: 1
                                                border.color: taskRow.task.done ? theme.accent : taskRow.hovered ? theme.alpha(theme.text, 0.55) : theme.alpha(theme.text, 0.26)
                                                Behavior on border.color { ColorAnimation { duration: Style.duration(120) } }
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: taskRow.task.done ? "✓" : ""
                                                    font.pixelSize: 11
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
                                            Layout.fillWidth: true; text: taskRow.task.title
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
                                            Layout.preferredWidth: 120; text: dash.dueDraft; font.pixelSize: 11
                                            onTextChanged: if (visible) dash.dueDraft = text
                                            onAccepted: { dash.commitDue(); page.forceActiveFocus(); }
                                            Keys.onEscapePressed: dash.dueTaskId = ""
                                            color: theme.text; font.family: theme.font; padding: 1
                                            background: Rectangle { color: theme.raised; radius: 2 }
                                        }
                                        Label {
                                            Layout.preferredWidth: 78
                                            horizontalAlignment: Text.AlignRight
                                            visible: dash.dueTaskId !== taskRow.task.id
                                            text: Dates.dueLabel(taskRow.task.due, dash.store.today)
                                            font.pixelSize: 11; elide: Text.ElideLeft
                                            color: (!taskRow.task.done && taskRow.task.due && taskRow.task.due < dash.store.today) ? theme.urgent : theme.muted
                                            MouseArea {
                                                anchors.fill: parent; hoverEnabled: true
                                                enabled: !taskRow.task.done
                                                onClicked: {
                                                    dash.editDue(taskRow.task);
                                                    Qt.callLater(function() { dueField.forceActiveFocus(); dueField.selectAll(); });
                                                }
                                            }
                                        }
                                        RowLayout {
                                            Layout.preferredWidth: 56; Layout.alignment: Qt.AlignVCenter
                                            spacing: 0; opacity: taskRow.hovered ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Style.duration(120) } }
                                            Glyph {
                                                text: "▶"; onClicked: dash.store.chooseFocus(taskRow.task.title, 1500)
                                                Accessible.name: "Focus on task"; ToolTip.visible: hovered; ToolTip.text: "Focus"
                                            }
                                            Glyph {
                                                text: dash.taskView === "Archive" ? "↩" : "⊟"
                                                onClicked: {
                                                    if (dash.taskView === "Archive") dash.store.restoreTask(taskRow.task.id);
                                                    else { dash.store.archiveTask(taskRow.task.id); Qt.callLater(dash.selectFirstTask); }
                                                }
                                                Accessible.name: dash.taskView === "Archive" ? "Restore task" : "Archive task"
                                                ToolTip.visible: hovered; ToolTip.text: dash.taskView === "Archive" ? "Restore" : "Archive"
                                            }
                                        }
                                    }
                                }
                                Label {
                                    anchors.centerIn: parent; width: parent.width; visible: parent.count === 0
                                    text: dash.taskView === "Archive" ? "Archive is empty." : dash.taskView === "Completed" ? "No completed tasks yet." : "Nothing here.\nAdd a task below."
                                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; opacity: 0.65; lineHeight: 1.5
                                }
                            }
                            // The right rail is intentionally provisional. It owns
                            // task context now; graph, notes or agenda can move in.
                            Item {
                                id: taskRail
                                visible: dash.focusedCard === "tasks"
                                anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: Math.round(parent.width * 0.40)
                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: theme.alpha(theme.text, 0.07)
                                }
                                ColumnLayout {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    anchors.leftMargin: 28; anchors.rightMargin: 28
                                    width: Math.min(taskRail.width - 56, 540)
                                    spacing: 0
                                    Label {
                                        visible: !!dash.selectedTask
                                        text: dash.taskStatus(dash.selectedTask)
                                        font.pixelSize: 11; font.letterSpacing: 1.4
                                        font.weight: Font.DemiBold
                                        color: dash.selectedTask && dash.selectedTask.due && !dash.selectedTask.done && dash.selectedTask.due < dash.store.today ? theme.urgent : theme.muted
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 10
                                        text: dash.selectedTask ? dash.selectedTask.title : "Select a task"
                                        font.pixelSize: 22; lineHeight: 1.15
                                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                    }
                                    RowLayout {
                                        Layout.topMargin: 10
                                        spacing: 10
                                        visible: !!dash.selectedTask
                                        Label {
                                            text: Dates.dueLabel(dash.selectedTask ? dash.selectedTask.due : "", dash.store.today) || "No due date"
                                            font.pixelSize: 12
                                            color: dash.selectedTask && dash.selectedTask.due && !dash.selectedTask.done && dash.selectedTask.due < dash.store.today ? theme.urgent : theme.alpha(theme.text, 0.62)
                                        }
                                        Repeater {
                                            model: dash.selectedTask ? (dash.selectedTask.tags || []) : []
                                            Label {
                                                required property var modelData
                                                text: "#" + modelData
                                                font.pixelSize: 12; color: theme.alpha(theme.text, 0.62)
                                            }
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 22
                                        visible: !!dash.selectedTask && !!dash.selectedTask.body
                                        text: dash.selectedTask ? dash.selectedTask.body : ""
                                        wrapMode: Text.Wrap; font.pixelSize: 13; lineHeight: 1.55
                                        color: theme.alpha(theme.text, 0.78)
                                    }
                                    Label {
                                        Layout.topMargin: 22
                                        visible: !dash.selectedTask || !dash.selectedTask.body
                                        text: "No notes on this task."
                                        font.pixelSize: 13
                                        color: theme.alpha(theme.text, 0.4)
                                    }
                                    Item { Layout.fillHeight: true }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        visible: !!dash.selectedTask
                                        Tab {
                                            text: "Focus 25m"
                                            onClicked: {
                                                dash.store.chooseFocus(dash.selectedTask.title, 1500);
                                                dash.focusedCard = "focus";
                                            }
                                        }
                                        Tab {
                                            text: "Edit"
                                            onClicked: dash.editTask(dash.selectedTask)
                                        }
                                        Item { Layout.fillWidth: true }
                                        Glyph {
                                            text: dash.selectedTask && dash.selectedTask.archived ? "↩" : "⊟"
                                            onClicked: {
                                                if (!dash.selectedTask) return;
                                                if (dash.selectedTask.archived) dash.store.restoreTask(dash.selectedTask.id);
                                                else { dash.store.archiveTask(dash.selectedTask.id); Qt.callLater(dash.selectFirstTask); }
                                            }
                                            Accessible.name: "Archive selected task"
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.rightMargin: dash.focusedCard === "tasks" ? Math.round(parent.width * 0.40) + 20 : 0
                            implicitHeight: 76; radius: 6
                            color: theme.alpha(theme.text, 0.035)
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
                        Label { text: "Focus"; font.pixelSize: 22; font.weight: Font.DemiBold }
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
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 16
                        Label { text: "Notepad"; font.pixelSize: 22; font.weight: Font.DemiBold }
                        RowLayout {
                            Label { Layout.fillWidth: true; text: dash.store.noteDay; font.pixelSize: 13; opacity: 0.7 }
                            Glyph { text: "‹"; onClicked: { page.forceActiveFocus(); dash.store.moveNoteDay(-1); } }
                            Tab { text: "Today"; onClicked: { page.forceActiveFocus(); dash.store.noteDay = dash.store.today; } }
                            Glyph { text: "›"; enabled: dash.store.noteDay < dash.store.today; onClicked: { page.forceActiveFocus(); dash.store.moveNoteDay(1); } }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.alpha(theme.text, 0.18) }
                        ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            TextArea {
                                id: notes; text: dash.store.note
                                onTextChanged: if (activeFocus) dash.store.setNote(text)
                                placeholderText: "Catch a thought.\nMake a little space."; placeholderTextColor: theme.muted
                                color: dash.textColor; wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 19
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
                        // The daily note is the index. Library notes dated to this day
                        // appear here; the @ button writes an explicit graph mention.
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.alpha(theme.text, 0.18) }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: "Today’s notes"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Label { text: dash.dayNotes.length ? dash.dayNotes.length + " linked" : "empty"; font.pixelSize: 11; opacity: 0.65 }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(132, dash.dayNotes.length * 44)
                            Layout.maximumHeight: 132
                            clip: true; spacing: 4
                            model: dash.dayNotes
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Item {
                                id: hubRow
                                required property var modelData
                                width: ListView.view.width; height: 44
                                Rectangle { anchors.fill: parent; radius: 3; color: hubArea.containsMouse ? theme.hover : theme.raised; opacity: hubArea.containsMouse ? 0.85 : 0.45 }
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 8; spacing: 8
                                    Label { Layout.fillWidth: true; text: "@" + hubRow.modelData.title; font.pixelSize: 13; color: theme.text; elide: Text.ElideRight }
                                    AbstractButton {
                                        id: hubLink
                                        z: 2; Layout.preferredWidth: 30; Layout.preferredHeight: 28
                                        hoverEnabled: true; focusPolicy: Qt.NoFocus
                                        Accessible.name: "Link " + hubRow.modelData.title + " in the daily note"
                                        ToolTip.visible: hovered; ToolTip.text: "Insert @mention in today’s note"
                                        onClicked: {
                                            notes.insert(notes.cursorPosition, "@" + hubRow.modelData.title + " ");
                                            dash.store.setNote(notes.text);
                                        }
                                        contentItem: Label { text: "@"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: theme.accent; font.pixelSize: 14 }
                                        background: Rectangle { radius: 3; color: hubLink.hovered ? theme.accent : "transparent" }
                                    }
                                }
                                MouseArea {
                                    id: hubArea; anchors.fill: parent; hoverEnabled: true
                                    onClicked: { dash.lastCard = "notes"; dash.store.showPulse("notes", hubRow.modelData.id); }
                                }
                            }
                            Label { anchors.centerIn: parent; width: parent.width; visible: parent.count === 0; text: "No notes dated today yet."; color: theme.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                        }
                        Label { text: (notes.text.trim() ? notes.text.trim().split(/\s+/).length : 0) + " words · Saved locally"; font.pixelSize: 12; opacity: 0.65 }
                        Label { text: "Ctrl+Enter → task"; font.pixelSize: 11; opacity: 0.5 }
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
                        Label { text: "Events"; font.pixelSize: 22; font.weight: Font.DemiBold }
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
                        Label { text: "Mail"; font.pixelSize: 22; font.weight: Font.DemiBold }
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
                id: notesLoader
                Layout.fillWidth: true; Layout.fillHeight: true
                active: dash.notesLoaded; asynchronous: true
                visible: dash.notesOpen
                opacity: dash.notesOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
                sourceComponent: Component { NotesPane { store: dash.store } }
            }
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
