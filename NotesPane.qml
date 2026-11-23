pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as Commons
import "Notes.js" as Notes

Item {
    id: pane
    required property var store
    property string query: ""
    property bool showArchived: false
    property var selected: null
    property string draftTitle: ""
    property string draftBody: ""
    property string draftTags: ""
    property string draftDate: ""

    Theme { id: theme }
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    readonly property var results: {
        store.revision;
        return store.searchNotes(pane.query, 100).filter(n => n.archived === pane.showArchived);
    }

    function select(item) {
        if (!item) return;
        if (Notes.isDaily(item.id)) {
            store.noteDay = item.date;
            store.showPulse("workspace");
            return;
        }
        pane.selected = item;
        pane.draftTitle = item.title || "";
        pane.draftBody = item.body || "";
        pane.draftTags = Notes.tagsText(item.tags || []);
        pane.draftDate = item.date || "";
    }
    function create() {
        pane.selected = {id: "", title: "", body: "", tags: [], date: null, archived: false, pinned: false, source: "library"};
        pane.draftTitle = ""; pane.draftBody = ""; pane.draftTags = ""; pane.draftDate = "";
        titleField.forceActiveFocus();
    }
    function save() {
        var title = pane.draftTitle.trim();
        if (!title) return;
        if (pane.selected && pane.selected.id) {
            store.updateNote(pane.selected.id, title, pane.draftBody, pane.draftTags, pane.draftDate);
        } else {
            var id = store.addNote(title, pane.draftBody, pane.draftTags, pane.draftDate);
            pane.selected = {id: id, title: title, body: pane.draftBody, tags: Notes.normaliseTags(pane.draftTags), date: pane.draftDate, archived: false, pinned: false, source: "library"};
        }
        pane.query = "";
    }
    function togglePin() {
        if (pane.selected && pane.selected.id) {
            store.toggleNotePin(pane.selected.id);
            pane.selected = Object.assign({}, pane.selected, {pinned: !pane.selected.pinned});
        }
    }
    function toggleArchive() {
        if (!pane.selected || !pane.selected.id) return;
        if (pane.selected.archived) {
            store.restoreNote(pane.selected.id);
            pane.selected = Object.assign({}, pane.selected, {archived: false});
        } else {
            store.archiveNote(pane.selected.id);
            pane.selected = null;
            pane.draftTitle = ""; pane.draftBody = ""; pane.draftTags = ""; pane.draftDate = "";
        }
    }

    component Copy: Text {
        color: theme.text; font.family: theme.font; font.pixelSize: 14
        textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    component Btn: AbstractButton {
        id: button
        implicitHeight: 36
        implicitWidth: Math.max(44, label.implicitWidth + 20)
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        background: Rectangle { radius: 3; color: button.hovered ? theme.hover : theme.raised; opacity: button.enabled ? 1 : 0.4 }
        contentItem: Copy { id: label; text: button.text; color: theme.text; wrapMode: Text.NoWrap }
    }
    component Field: TextField {
        color: theme.text; font.family: theme.font; font.pixelSize: 15
        placeholderTextColor: theme.muted; padding: 10; implicitHeight: 42
        selectionColor: theme.accent; selectedTextColor: theme.background
        background: Rectangle { radius: 3; color: theme.raised; border.width: parent.activeFocus ? 1 : 0; border.color: theme.accent }
    }

    Rectangle { anchors.fill: parent; color: theme.background }
    RowLayout {
        anchors.fill: parent; anchors.margins: 24; spacing: 18
        ColumnLayout {
            Layout.preferredWidth: 360; Layout.fillHeight: true; spacing: 12
            Copy { text: strings.t("notes.title"); font.pixelSize: 24; font.bold: true; Layout.fillWidth: false }
            Field { id: searchField; Layout.fillWidth: true; placeholderText: strings.t("notes.search"); onTextChanged: pane.query = text }
            RowLayout {
                Btn {
                    text: strings.t("notes.active")
                    onClicked: pane.showArchived = false
                    background: Rectangle { radius: 3; color: !pane.showArchived ? theme.accent : theme.raised }
                }
                Btn {
                    text: strings.t("notes.archived")
                    onClicked: pane.showArchived = true
                    background: Rectangle { radius: 3; color: pane.showArchived ? theme.accent : theme.raised }
                }
                Btn { text: strings.t("notes.new"); onClicked: pane.create() }
                Copy { text: strings.tn("notes.count", pane.results.length); color: theme.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                model: pane.results
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: row
                    required property var modelData
                    property bool isHovered: false
                    width: ListView.view.width; height: 76
                    Rectangle { anchors.fill: parent; color: row.isHovered ? theme.hover : theme.raised; opacity: row.isHovered ? 0.9 : 0.45 }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 2
                        Copy {
                            text: (row.modelData.pinned ? "★ " : "") + (row.modelData.title || strings.t("notes.untitled"))
                            font.bold: true; color: theme.text
                        }
                        Copy { text: Notes.excerpt(row.modelData.body, 80); font.pixelSize: 12; color: theme.muted; maximumLineCount: 2; elide: Text.ElideRight }
                        Copy {
                            text: [row.modelData.date, (row.modelData.tags || []).map(t => "#" + t).join(" ")].filter(Boolean).join(" · ")
                            font.pixelSize: 11; color: theme.muted; visible: !!text
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: row.isHovered = true
                        onExited: row.isHovered = false
                        onClicked: pane.select(row.modelData)
                    }
                }
                Copy { anchors.centerIn: parent; width: parent.width; visible: parent.count === 0; text: strings.t("notes.empty"); color: theme.muted; horizontalAlignment: Text.AlignHCenter }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
            enabled: !!pane.selected
            Field { id: titleField; Layout.fillWidth: true; placeholderText: strings.t("notes.titleField"); text: pane.draftTitle; onTextChanged: pane.draftTitle = text }
            RowLayout {
                Field { id: tagsField; Layout.fillWidth: true; placeholderText: strings.t("notes.tagsField"); text: pane.draftTags; onTextChanged: pane.draftTags = text }
                Field { id: dateField; Layout.preferredWidth: 190; placeholderText: strings.t("notes.dateField"); text: pane.draftDate; maximumLength: 10; onTextChanged: pane.draftDate = text }
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                TextArea {
                    id: bodyField
                    text: pane.draftBody
                    onTextChanged: pane.draftBody = text
                    placeholderText: strings.t("notes.bodyField")
                    color: theme.text; font.family: theme.font; font.pixelSize: 17
                    wrapMode: TextEdit.Wrap; padding: 12
                    background: Rectangle { radius: 3; color: theme.raised }
                    selectionColor: theme.accent; selectedTextColor: theme.background
                }
            }
            RowLayout {
                Btn { text: strings.t("notes.save"); onClicked: pane.save() }
                Btn { text: pane.selected && pane.selected.pinned ? strings.t("notes.unpin") : strings.t("notes.pin"); onClicked: pane.togglePin() }
                Btn { text: pane.selected && pane.selected.archived ? strings.t("notes.restore") : strings.t("notes.archive"); onClicked: pane.toggleArchive() }
                Item { Layout.fillWidth: true }
                Copy { text: pane.selected && pane.selected.id ? pane.selected.id : ""; color: theme.muted; font.pixelSize: 11 }
            }
        }
    }
}
