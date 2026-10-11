import QtQuick
import QtQuick.Controls

Button {
    id: button
    required property var service
    required property var conversation
    Theme { id: theme }
    text: "✓"; implicitWidth: 28; implicitHeight: 26; focusPolicy: Qt.NoFocus
    enabled: !service.busy
    Accessible.name: "Mark conversation read: " + conversation.name
    ToolTip.visible: hovered; ToolTip.text: "Mark read"; ToolTip.delay: 350
    background: Rectangle { color: button.hovered ? theme.accent : theme.raised; radius: 3; opacity: button.enabled ? 1 : 0.4 }
    contentItem: Text { text: button.text; color: button.hovered ? theme.background : theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 15 }
    onClicked: service.markRead(conversation)
}
