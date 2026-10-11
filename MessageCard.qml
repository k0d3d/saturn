pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: card
    required property var store
    readonly property var service: store.messages
    signal showAllRequested()
    Theme { id: theme }
    spacing: 14
    component Copy: Text {
        color: theme.text; font.family: theme.font; font.pixelSize: 14
        textFormat: Text.PlainText; elide: Text.ElideRight
    }
    component Action: Button {
        id: action
        property bool selected: false
        focusPolicy: Qt.NoFocus; implicitHeight: 38
        background: Rectangle { color: action.selected ? theme.accent : action.hovered ? theme.hover : theme.raised; radius: 3; opacity: action.enabled ? 1 : 0.4 }
        contentItem: Copy { text: action.text; color: action.selected ? theme.background : theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    RowLayout {
        Copy { text: "Messages"; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true }
        MessageSourceMenu { service: card.service }
        Action { text: "↻"; implicitWidth: 38; enabled: !card.service.busy; onClicked: card.service.refresh(); Accessible.name: "Refresh messages" }
    }
    Copy {
        Layout.fillWidth: true; font.pixelSize: 12; color: theme.muted
        text: card.service.busy ? "Checking messages…" : card.service.sourceSummary + " · " + card.service.unread + " unread"
    }
    RowLayout {
        Layout.fillWidth: true
        Action { Layout.fillWidth: true; text: "Key"; selected: card.service.keyOnly; implicitHeight: 30; onClicked: card.service.setKeyOnly(true) }
        Action { Layout.fillWidth: true; text: "All"; selected: !card.service.keyOnly; implicitHeight: 30; onClicked: card.service.setKeyOnly(false) }
    }
    ListView {
        id: conversations; objectName: "workspace-messages"
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
        model: card.service.rows
        ScrollBar.vertical: ScrollBar {}
        delegate: AbstractButton {
            id: chatRow
            required property var modelData
            width: ListView.view.width; height: 120
            padding: 12; hoverEnabled: true; focusPolicy: Qt.NoFocus
            enabled: !card.service.busy
            Accessible.name: "Open conversation: " + modelData.name + ", " + modelData.unread + " unread"
            background: Rectangle { color: chatRow.hovered ? theme.hover : theme.raised; radius: 3 }
            contentItem: ColumnLayout {
                spacing: 6
                RowLayout {
                    Copy { Layout.fillWidth: true; text: chatRow.modelData.name; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Copy { text: chatRow.modelData.unread; color: theme.accent; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    MessageReadButton { service: card.service; conversation: chatRow.modelData }
                    MessageRuleButton { service: card.service; conversation: chatRow.modelData }
                }
                Copy { Layout.fillWidth: true; text: chatRow.modelData.preview; wrapMode: Text.Wrap; maximumLineCount: 2; font.pixelSize: 13 }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Copy { Layout.fillWidth: true; text: chatRow.modelData.network; color: theme.muted; font.pixelSize: 11 }
                    Copy { text: isNaN(Date.parse(chatRow.modelData.timestamp)) ? "" : Qt.formatDateTime(new Date(chatRow.modelData.timestamp), "MMM d"); color: theme.muted; font.pixelSize: 10 }
                }
            }
            onClicked: card.service.openConversation(modelData)
        }
        Copy {
            anchors.centerIn: parent; width: parent.width; visible: conversations.count === 0
            wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: theme.muted
            text: card.service.busy || !card.service.updated ? "Checking messages…"
                : card.service.error ? "Messages are temporarily unavailable."
                : !card.service.anySource ? "Choose a message source above."
                : !(card.service.textsEnabled && card.service.blip.connected) && !((card.service.slackEnabled || card.service.beeperEnabled) && card.service.beeper.connected) ? "Connect your selected sources\nin Connections."
                : card.service.keyOnly && card.service.hiddenCount ? "No key messages.\nSwitch to All to see filtered chats."
                : "You’re all caught up."
        }
    }
    Copy {
        Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; font.pixelSize: 11; color: theme.muted
        text: card.service.error || (card.service.textsEnabled && card.service.blip.error ? card.service.blip.error : "")
            || ((card.service.slackEnabled || card.service.beeperEnabled) && card.service.beeper.error ? card.service.beeper.error : "")
            || (card.service.hiddenCount ? card.service.hiddenCount + " chats outside Key · View All" : card.service.sourceSummary)
    }
    Action { Layout.fillWidth: true; text: "Open messages"; onClicked: card.showAllRequested() }
}
