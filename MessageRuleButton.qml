import QtQuick
import QtQuick.Controls

Button {
    id: button
    required property var service
    required property var conversation
    Theme { id: theme }
    text: "⋯"; implicitWidth: 30; implicitHeight: 26; focusPolicy: Qt.NoFocus
    Accessible.name: "Message filter options for " + conversation.name
    background: Rectangle { color: button.hovered ? theme.hover : theme.raised; radius: 3 }
    contentItem: Text { text: button.text; color: theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 18 }
    onClicked: options.popup()
    Menu {
        id: options
        palette.window: theme.background; palette.base: theme.background
        palette.text: theme.text; palette.windowText: theme.text; palette.buttonText: theme.text
        palette.highlight: theme.accent; palette.highlightedText: theme.background
        MenuItem { text: "Always keep in Key"; checkable: true; checked: button.service.ruleFor(button.conversation) === "keep"; onTriggered: button.service.setRule(button.conversation,"keep") }
        MenuItem { text: "Hide from Key"; checkable: true; checked: button.service.ruleFor(button.conversation) === "hide"; onTriggered: button.service.setRule(button.conversation,"hide") }
        MenuItem { text: "Use automatic filter"; checkable: true; checked: button.service.ruleFor(button.conversation) === "auto"; onTriggered: button.service.setRule(button.conversation,"auto") }
    }
}
