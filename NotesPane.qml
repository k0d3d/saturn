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

    readonly property var tints: [
        Qt.rgba(0.36, 0.55, 0.94, 1),
        Qt.rgba(0.34, 0.78, 0.52, 1),
        Qt.rgba(0.69, 0.49, 1.00, 1),
        Qt.rgba(0.90, 0.72, 0.36, 1),
        Qt.rgba(0.88, 0.42, 0.46, 1),
        Qt.rgba(0.50, 0.82, 0.90, 1)
    ]
    readonly property var results: {
        store.revision;
        return store.searchNotes(pane.query, 100).filter(n => n.archived === pane.showArchived);
    }

    Connections {
        target: store
        function onNotesQueryChanged() {
            pane.query = store.notesQuery;
            searchField.text = store.notesQuery;
        }
        function onNotesSelectionChanged() {
            if (!store.notesSelection) { pane.selected = null; return; }
            var item = store.searchNotes("", 100).find(n => n.id === store.notesSelection);
            if (item) pane.select(item);
        }
    }

    function tintFor(id) {
        var text = String(id || ""), hash = 0;
        for (var i = 0; i < text.length; i++) hash = (hash * 31 + text.charCodeAt(i)) >>> 0;
        return pane.tints[hash % pane.tints.length];
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
    function back() {
        pane.selected = null;
        store.notesSelection = "";
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
        if (!pane.selected || !pane.selected.id) return;
        store.toggleNotePin(pane.selected.id);
        pane.selected = Object.assign({}, pane.selected, {pinned: !pane.selected.pinned});
    }
    function toggleArchive() {
        if (!pane.selected || !pane.selected.id) return;
        if (pane.selected.archived) {
            store.restoreNote(pane.selected.id);
            pane.selected = Object.assign({}, pane.selected, {archived: false});
        } else {
            store.archiveNote(pane.selected.id);
            pane.back();
        }
    }

    component Copy: Text {
        color: theme.text; font.family: theme.font; font.pixelSize: 14
        textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    component Btn: AbstractButton {
        id: button
        property bool selected: false
        implicitHeight: 30
        implicitWidth: Math.max(28, label.implicitWidth + 14)
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        background: Item {
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 2; color: button.selected ? theme.accent : button.hovered ? theme.alpha(theme.text, 0.28) : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }
        contentItem: Text {
            id: label; text: button.text; font.family: theme.font; font.pixelSize: 14
            font.weight: button.selected ? Font.DemiBold : Font.Normal
            color: button.selected || button.hovered ? theme.text : theme.muted
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
    }
    component Field: TextField {
        color: theme.text; font.family: theme.font; font.pixelSize: 13
        placeholderTextColor: theme.muted; padding: 8; implicitHeight: 36
        selectionColor: theme.accent; selectedTextColor: theme.background
        background: Rectangle {
            radius: 4; color: theme.alpha(theme.text, 0.04)
            border.width: 1; border.color: parent.activeFocus ? theme.accent : theme.alpha(theme.text, 0.10)
        }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 26; spacing: 14

        RowLayout {
            Layout.fillWidth: true
            Copy { Layout.fillWidth: true; text: strings.t("notes.title"); font.pixelSize: 26; font.bold: true }
            Copy {
                Layout.fillWidth: false
                text: strings.tn("notes.count", pane.results.length)
                color: theme.muted; font.pixelSize: 11; horizontalAlignment: Text.AlignRight
            }
            Btn { text: "＋ " + strings.t("notes.new"); onClicked: pane.create() }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Field {
                id: searchField
                Layout.preferredWidth: 380
                placeholderText: strings.t("notes.search")
                text: store.notesQuery
                onTextChanged: { pane.query = text; store.notesQuery = text }
            }
            Btn { text: strings.t("notes.active"); selected: !pane.showArchived; onClicked: pane.showArchived = false }
            Btn { text: strings.t("notes.archived"); selected: pane.showArchived; onClicked: pane.showArchived = true }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Board: full width, one card per note.
            GridView {
                id: board
                anchors.fill: parent
                visible: pane.selected === null
                clip: true
                model: pane.results
                readonly property int columns: Math.max(1, Math.min(4, Math.floor(width / 320)))
                cellWidth: Math.max(240, Math.floor(width / columns))
                cellHeight: 208
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded; width: 4
                    background: null
                    contentItem: Rectangle { implicitWidth: 4; radius: 2; color: theme.alpha(theme.text, 0.28) }
                }
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: GridView.view.cellWidth - 12
                    height: 196
                    radius: 6
                    color: theme.alpha(pane.tintFor(card.modelData.id), 0.15)
                    border.width: 1
                    border.color: cardHover.hovered ? theme.alpha(pane.tintFor(card.modelData.id), 0.55)
                                                    : theme.alpha(pane.tintFor(card.modelData.id), 0.26)
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 6
                        RowLayout {
                            spacing: 6
                            Image {
                                source: Qt.resolvedUrl(Notes.isDaily(card.modelData.id) ? "assets/icons/notebook-pen.svg" : "assets/icons/file-text.svg")
                                sourceSize.width: 24; sourceSize.height: 24
                                Layout.preferredWidth: 12; Layout.preferredHeight: 12
                                opacity: 0.55
                            }
                            Copy {
                                Layout.fillWidth: true
                                text: card.modelData.date || ""
                                color: theme.muted; font.pixelSize: 10
                            }
                            Copy {
                                Layout.fillWidth: false
                                visible: !!card.modelData.pinned
                                text: "PINNED"; font.pixelSize: 9; font.letterSpacing: 1
                                color: theme.accent
                            }
                        }
                        Copy {
                            text: card.modelData.title || strings.t("notes.untitled")
                            font.pixelSize: 15; font.bold: true
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                        Copy {
                            Layout.fillHeight: true
                            text: Notes.excerpt(card.modelData.body, 260) || "No text yet."
                            color: theme.muted; font.pixelSize: 12; lineHeight: 1.45
                            maximumLineCount: 5; elide: Text.ElideRight
                        }
                        Copy {
                            Layout.fillWidth: false
                            visible: !!text
                            text: (card.modelData.tags || []).map(t => "#" + t).join("  ")
                            color: theme.muted; font.pixelSize: 10
                        }
                    }
                    HoverHandler { id: cardHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.select(card.modelData)
                    }
                }
                Copy {
                    anchors.centerIn: parent; width: parent.width
                    visible: parent.count === 0
                    text: strings.t("notes.empty")
                    color: theme.muted; horizontalAlignment: Text.AlignHCenter
                }
            }

            // Editor: one note, one column; the board is not kept beside it.
            ColumnLayout {
                anchors.top: parent.top; anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 920)
                visible: pane.selected !== null
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Btn { text: "‹ " + strings.t("notes.all"); onClicked: pane.back() }
                    Item { Layout.fillWidth: true }
                    Btn {
                        text: pane.selected && pane.selected.pinned ? strings.t("notes.unpin") : strings.t("notes.pin")
                        onClicked: pane.togglePin()
                    }
                    Btn {
                        text: pane.selected && pane.selected.archived ? strings.t("notes.restore") : strings.t("notes.archive")
                        onClicked: pane.toggleArchive()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: titleField.implicitHeight + 10
                    TextField {
                        id: titleField
                        anchors.fill: parent
                        placeholderText: strings.t("notes.titleField")
                        text: pane.draftTitle
                        onTextChanged: pane.draftTitle = text
                        color: theme.text; font.family: theme.font; font.pixelSize: 26; font.weight: Font.DemiBold
                        padding: 0; background: null
                        selectionColor: theme.accent; selectedTextColor: theme.background
                    }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 1; color: theme.alpha(theme.text, 0.14) }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Field {
                        id: tagsField; Layout.fillWidth: true
                        placeholderText: strings.t("notes.tagsField")
                        text: pane.draftTags
                        onTextChanged: pane.draftTags = text
                    }
                    Field {
                        id: dateField; Layout.preferredWidth: 170
                        placeholderText: strings.t("notes.dateField")
                        text: pane.draftDate; maximumLength: 10
                        onTextChanged: pane.draftDate = text
                    }
                }

                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    TextArea {
                        id: bodyField
                        text: pane.draftBody
                        onTextChanged: pane.draftBody = text
                        placeholderText: strings.t("notes.bodyField")
                        color: theme.text; font.family: theme.font; font.pixelSize: 16
                        wrapMode: TextEdit.Wrap; padding: 0; background: null
                        selectionColor: theme.accent; selectedTextColor: theme.background
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Rectangle {
                        width: saveLabel.implicitWidth + 24; height: 30; radius: 4
                        color: theme.accent
                        Text {
                            id: saveLabel; anchors.centerIn: parent
                            text: strings.t("notes.save")
                            color: theme.background; font.family: theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pane.save() }
                    }
                    Item { Layout.fillWidth: true }
                    Copy {
                        Layout.fillWidth: false
                        text: (pane.draftBody.trim() ? pane.draftBody.trim().split(/\s+/).length : 0) + " words"
                        color: theme.muted; font.pixelSize: 11
                    }
                }
            }
        }
    }
}
