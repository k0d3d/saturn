import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property var service
    text: "Sources"
    implicitHeight: 34
    Accessible.name: "Choose message sources"
    onClicked: menu.open()
    Menu {
        id: menu
        y: root.height
        MenuItem { text: "Text messages (Blip)"; checkable: true; checked: root.service.textsEnabled; onTriggered: root.service.setSource("texts",checked) }
        MenuItem { text: "Slack (via Beeper)"; checkable: true; checked: root.service.slackEnabled; onTriggered: root.service.setSource("slack",checked) }
        MenuItem { text: "Other Beeper messages"; checkable: true; checked: root.service.beeperEnabled; onTriggered: root.service.setSource("beeper",checked) }
    }
}
