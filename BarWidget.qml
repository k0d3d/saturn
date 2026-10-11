pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "kosta.omaowl"
    Theme { id: voiceTheme }
    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property var panel: service ? service.windowForScreen(screenName) : null
    // Replacement bars expose a service-less facade. Use the plugin's IPC
    // interface there, keeping all window decisions in the live service.
    property var remoteState: ({})
    readonly property bool opened: panel ? panel.expanded || panel.dashboardOpen || panel.commandOpen : !!remoteState.opened
    readonly property bool focusRunning: service ? service.focusState.running : !!remoteState.running
    readonly property bool voiceEnabled: service ? service.voiceActive : !!remoteState.voiceEnabled
    readonly property string voicePhase: service ? service.activeVoicePhase : (remoteState.voicePhase || "off")
    readonly property string voiceName: service ? service.activeVoiceName : (remoteState.voiceName || "Grok live")
    function remoteAction(action) {
        Quickshell.execDetached(["omarchy-shell", "omapulse", "barAction", screenName, action]);
        refreshAfterAction.restart();
    }
    function refreshState() { if (!service && !stateProcess.running) stateProcess.running = true; }
    function open() { if (panel) { panel.pinned = true; panel.open(); } else remoteAction("open"); }
    function close() { if (panel) { panel.commandOpen = false; panel.dashboardOpen = false; panel.close(); } else remoteAction("close"); }
    Component.onCompleted: refreshState()
    onScreenNameChanged: refreshState()
    Process {
        id: stateProcess
        command: ["omarchy-shell", "omapulse", "barState", root.screenName]
        stdout: StdioCollector {
            onStreamFinished: { try { root.remoteState = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer { interval: 2000; repeat: true; running: !root.service; onTriggered: root.refreshState() }
    Timer { id: refreshAfterAction; interval: 150; onTriggered: root.refreshState() }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component { Image { source: Qt.resolvedUrl("assets/omapulse.svg"); fillMode: Image.PreserveAspectFit } }
        active: root.opened || root.focusRunning
        interactive: true
        tooltipText: (root.focusRunning ? "Oma Pulse · " + (root.service ? root.service.timerText : root.remoteState.timer) : "Oma Pulse · Tasks, focus, notes and calendar") + "\n" + root.voiceName + " · " + (root.voiceEnabled ? root.voicePhase : "off") + "\nEsc: end Grok · Ctrl+Alt+P: toggle Grok"
        onTooltipHoveredChanged: {
            if (tooltipHovered && !root.opened) hoverTimer.restart();
            else hoverTimer.stop();
        }
        onPressed: function(mouseButton) {
            hoverTimer.stop();
            if (!root.panel) {
                if (mouseButton === Qt.RightButton) root.remoteAction("dashboard");
                else if (mouseButton === Qt.LeftButton) root.remoteAction("click");
                return;
            }
            if (mouseButton === Qt.RightButton) root.panel.openDashboard();
            else if (mouseButton === Qt.LeftButton) {
                if (root.opened && root.panel.pinned) root.close();
                else root.open();
            }
        }
    }
    Rectangle { anchors.right:parent.right; anchors.bottom:parent.bottom; width:5; height:5; radius:3; color:root.voicePhase === "error" ? voiceTheme.urgent : voiceTheme.accent; visible:root.voiceEnabled }
    Timer {
        id: hoverTimer; interval: 240
        onTriggered: if (button.tooltipHovered && !root.opened) {
            button.hideOwnTooltip();
            if (root.panel) root.panel.open();
            else root.remoteAction("hover");
        }
    }
    onOpenedChanged: if (opened) button.hideOwnTooltip()
}
