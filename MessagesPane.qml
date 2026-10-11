pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: pane
    required property var store
    signal setupRequested()
    readonly property var rows: store.messages.rows
    Theme { id: theme }
    spacing: 14
    component Copy: Label {
        color: theme.text; font.family: theme.font; font.pixelSize: 15
        textFormat: Text.PlainText; wrapMode: Text.Wrap
    }
    component Action: Button {
        id: button
        property bool selected: false
        implicitHeight: 38
        background: Rectangle { color: button.selected ? theme.accent : button.hovered ? theme.hover : theme.raised; radius: 3; opacity: button.enabled ? 1 : 0.4 }
        contentItem: Copy { text: button.text; color: button.selected ? theme.background : theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; leftPadding: 12; rightPadding: 12 }
    }
    RowLayout {
        Layout.fillWidth: true
        Copy { text: "Messages"; font.pixelSize: 25; font.bold: true }
        Copy { text: pane.store.messages.busy ? "Refreshing…" : pane.rows.length + " unread conversations"; color: theme.muted; Layout.fillWidth: true }
        Action { text: "Refresh"; enabled: !pane.store.messages.busy; onClicked: pane.store.messages.refresh() }
        Action { text: "Connections"; onClicked: pane.setupRequested() }
    }
    RowLayout {
        Action { text: "Key messages"; selected: pane.store.messages.keyOnly; onClicked: pane.store.messages.setKeyOnly(true) }
        Action { text: "All messages"; selected: !pane.store.messages.keyOnly; onClicked: pane.store.messages.setKeyOnly(false) }
        CheckBox {
            text: "Keep useful alerts"; checked: pane.store.messages.keepAlerts
            onToggled: pane.store.messages.setKeepAlerts(checked)
            palette.windowText: theme.text; palette.text: theme.text; palette.highlight: theme.accent
        }
        Copy { text: pane.store.messages.hiddenCount + " conversations outside Key"; color: theme.muted; Layout.fillWidth: true }
    }
    RowLayout {
        MessageSourceMenu { service: pane.store.messages }
        Copy { text: pane.store.messages.sourceSummary + " · Changes also apply to your workspace widget."; color: theme.muted; Layout.fillWidth: true }
    }
    Copy { visible: !!pane.store.messages.error; text: pane.store.messages.error; color: theme.urgent; Layout.fillWidth: true }
    Copy { visible: !!pane.store.messages.blip.error && pane.store.messages.textsEnabled; text: "Blip · " + pane.store.messages.blip.error; color: theme.muted; Layout.fillWidth: true }
    Copy { visible: !!pane.store.messages.beeper.error && (pane.store.messages.slackEnabled || pane.store.messages.beeperEnabled); text: "Beeper · " + pane.store.messages.beeper.error; color: theme.muted; Layout.fillWidth: true }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
        model: pane.rows
        ScrollBar.vertical: ScrollBar {}
        delegate: AbstractButton {
            id: row
            required property var modelData
            width: ListView.view.width; implicitHeight: content.implicitHeight + 28
            hoverEnabled: true; enabled: !pane.store.messages.busy
            Accessible.name: modelData.name + ", " + modelData.unread + " unread. Open in " + (modelData.source === "blip" ? "Blip" : "Beeper")
            background: Rectangle { color: row.hovered ? theme.hover : theme.raised; border.color: theme.border; border.width: 1 }
            contentItem: ColumnLayout {
                id: content; spacing: 6
                RowLayout {
                    spacing: 16
                    Copy { text: row.modelData.name; font.bold: true; Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideRight }
                    Copy { text: row.modelData.network + " · " + row.modelData.unread + " unread"; color: theme.accent }
                    Copy { text: isNaN(Date.parse(row.modelData.timestamp)) ? "" : Qt.formatDateTime(new Date(row.modelData.timestamp), "MMM d, h:mm AP"); color: theme.muted; font.pixelSize: 12 }
                    MessageReadButton { service: pane.store.messages; conversation: row.modelData }
                    MessageRuleButton { service: pane.store.messages; conversation: row.modelData }
                }
                Copy { text: row.modelData.preview; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight; color: theme.muted }
                Copy { visible: !pane.store.messages.keyOnly && !!text; text: pane.store.messages.hiddenReason(row.modelData); color: theme.muted; font.pixelSize: 12 }
            }
            leftPadding: 16; rightPadding: 16; topPadding: 14; bottomPadding: 14
            onClicked: pane.store.messages.openConversation(modelData)
        }
        Copy {
            anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter
            visible: pane.rows.length === 0 && !pane.store.messages.busy
            text: !pane.store.messages.anySource ? "Choose a message source above." : !pane.store.messages.updated ? "Loading your messages…" : pane.store.messages.keyOnly ? "No key messages in this view. Switch to All messages to review filtered chats." : "No unread previews from connected sources."
            color: theme.muted
        }
    }
}
