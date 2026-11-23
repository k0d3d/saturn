pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import "Logic.js" as Logic
import "Intents.js" as Intents

PanelWindow {
    id: win
    required property var store
    signal dismissed()
    signal workspaceRequested()

    property string query: ""
    readonly property var noteResults: store.searchNotes(win.query, 12)
    readonly property var taskResults: win.query.trim()
        ? Logic.tasksInView(store.tasks, "All", store.today).filter(t => t.title.toLowerCase().indexOf(win.query.toLowerCase()) >= 0).slice(0, 8)
        : []

    Theme { id: theme }
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    anchors.top: true
    margins.top: Commons.Style.bar.sizeHorizontal + 10
    implicitWidth: Math.min(800, screen.width - 40)
    implicitHeight: 300
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "saturn-command"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    onVisibleChanged: if (visible) { input.text = ""; win.query = ""; Qt.callLater(() => input.forceActiveFocus()); }

    function runAction(action, text) {
        if (!action) { store.addTask(text); return; }
        switch (action.kind) {
        case "add_task": store.addTask(action.value || text); break;
        case "start_focus":
            store.chooseFocus(action.value || store.focusState.title, (action.number || 25) * 60);
            store.toggleTimer(); break;
        case "pause_focus":
        case "resume_focus":
            if (store.focusState.running !== (action.kind === "resume_focus")) store.toggleTimer();
            break;
        case "append_note":
            store.noteDay = store.today;
            store.setNote(store.note + (store.note ? "\n" : "") + action.value);
            break;
        case "show_day":
        case "show_pulse":
            store.showPulse(action.kind === "show_day" ? "workspace" : action.value);
            break;
        default: store.addTask(text);
        }
    }
    function submit() {
        var text = input.text.trim();
        if (!text) return;
        runAction(Intents.parse(text, store.today), text);
        input.text = "";
        dismissed();
    }

    component Label: Text {
        color: theme.text; font.family: theme.font; font.pixelSize: 14
        textFormat: Text.PlainText; elide: Text.ElideRight
    }
    component Btn: AbstractButton {
        id: button
        implicitHeight: 32
        background: Rectangle { radius: 3; color: button.hovered ? theme.hover : theme.raised }
        contentItem: Label { text: button.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }

    Rectangle { anchors.fill: parent; color: theme.background; border.width: 1; border.color: theme.border }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 18; spacing: 10
        RowLayout {
            Label { text: "◉  Saturn"; color: theme.accent; font.bold: true; font.pixelSize: 16 }
            Item { Layout.fillWidth: true }
            Btn { text: strings.t("command.workspace"); onClicked: { workspaceRequested(); dismissed(); } }
            Btn { text: "×"; onClicked: dismissed() }
        }
        TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: strings.t("command.placeholder")
            color: theme.text; font.family: theme.font; font.pixelSize: 18
            selectionColor: theme.accent; selectedTextColor: theme.background
            background: Rectangle { radius: 3; color: theme.raised }
            onTextChanged: win.query = text
            onAccepted: win.submit()
        }
        RowLayout {
            Btn { text: strings.t("command.addTask"); onClicked: win.submit() }
            Btn { text: strings.t("command.notes"); onClicked: { store.notesSearch(win.query); dismissed(); } }
            Item { Layout.fillWidth: true }
            Label { text: strings.t("command.hint"); color: theme.muted; font.pixelSize: 11 }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            ColumnLayout {
                width: parent ? parent.width : 0
                spacing: 6
                Label { visible: win.taskResults.length > 0; text: strings.t("command.tasks"); color: theme.muted; font.pixelSize: 11 }
                Repeater {
                    model: win.taskResults
                    delegate: Btn {
                        required property var modelData
                        Layout.fillWidth: true
                        text: (modelData.done ? "✓ " : "○ ") + modelData.title
                        onClicked: { store.toggleTask(modelData.id); dismissed(); }
                    }
                }
                Label { visible: win.noteResults.length > 0; text: strings.t("command.notes"); color: theme.muted; font.pixelSize: 11 }
                Repeater {
                    model: win.noteResults
                    delegate: Btn {
                        required property var modelData
                        Layout.fillWidth: true
                        text: (modelData.pinned ? "★ " : "") + modelData.title
                        onClicked: {
                            if (modelData.source === "daily") { store.noteDay = modelData.date; store.showPulse("workspace"); }
                            else store.notesSearch(modelData.title);
                            dismissed();
                        }
                    }
                }
                Label { visible: !!win.query.trim() && win.taskResults.length === 0 && win.noteResults.length === 0; text: strings.t("command.noResults"); color: theme.muted }
            }
        }
    }
}
