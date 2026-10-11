import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

PanelWindow {
    id: hud
    required property var voice
    property bool liveConversation: false
    visible: voice.overlayVisible
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors.top: true
    margins.top: Style.bar.sizeHorizontal+12
    implicitWidth: 480; implicitHeight: content.implicitHeight+30
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "oma-pulse-voice"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    Theme { id: theme }
    Rectangle { anchors.fill:parent; color:Qt.rgba(theme.background.r,theme.background.g,theme.background.b,1); border.color:theme.accent; border.width:1; radius:0 }
    ColumnLayout {
        id:content; anchors.left:parent.left; anchors.right:parent.right; anchors.top:parent.top; anchors.margins:15; spacing:7
        RowLayout {
            Rectangle { implicitWidth:8; implicitHeight:8; radius:4; color:hud.voice.phase === "error" ? theme.urgent : theme.accent }
            Text { text:"Pulse"; font.family:theme.font; font.pixelSize:16; font.bold:true; color:theme.text; Layout.fillWidth:true }
            Button { visible:hud.liveConversation || ["speaking","followup","listening"].indexOf(hud.voice.phase) >= 0; text:hud.liveConversation ? "End chat · Esc" : "Stop · Esc"; implicitHeight:28; onClicked: hud.voice.stopSpeaking() }
            Button { text:"Mic off"; implicitHeight:28; onClicked:hud.voice.setEnabled(false) }
        }
        Text { text:hud.voice.statusText; textFormat:Text.PlainText; color:theme.text; font.family:theme.font; font.pixelSize:14; wrapMode:Text.Wrap; maximumLineCount:3; elide:Text.ElideRight; Layout.fillWidth:true }
        Text { visible:!!hud.voice.heard; text:hud.voice.heard; textFormat:Text.PlainText; color:theme.muted; font.family:theme.font; font.pixelSize:12; wrapMode:Text.Wrap; maximumLineCount:2; elide:Text.ElideRight; Layout.fillWidth:true }
    }
}
