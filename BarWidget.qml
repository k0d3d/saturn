pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "k0d3d.saturn"
    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property var panel: service ? service.windowForScreen(screenName) : null
    // Replacement bars expose a service-less facade. Use the plugin's IPC
    // interface there, keeping all window decisions in the live service.
    property var remoteState: ({})
    readonly property bool opened: panel ? panel.dashboardOpen || panel.commandOpen : !!remoteState.opened
    readonly property bool focusRunning: service ? service.focusState.running : !!remoteState.running
    function remoteAction(action) {
        Quickshell.execDetached(["omarchy-shell", "saturn", "barAction", screenName, action]);
        refreshAfterAction.restart();
    }
    function refreshState() { if (!service && !stateProcess.running) stateProcess.running = true; }
    function open() { if (panel) panel.openDashboard(); else remoteAction("open"); }
    function close() { if (panel) panel.close(); else remoteAction("close"); }
    Component.onCompleted: refreshState()
    onScreenNameChanged: refreshState()
    Process {
        id: stateProcess
        command: ["omarchy-shell", "saturn", "barState", root.screenName]
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
        iconComponent: Component { Image { source: Qt.resolvedUrl("assets/saturn.png"); fillMode: Image.PreserveAspectFit } }
        active: root.opened || root.focusRunning
        interactive: true
        tooltipText: (root.focusRunning ? "Saturn · " + (root.service ? root.service.timerText : root.remoteState.timer) : "Saturn · Tasks, focus, notes and calendar") + "\nClick for the full workspace"
        onPressed: function(mouseButton) {
            if (mouseButton !== Qt.LeftButton && mouseButton !== Qt.RightButton) return;
            if (root.opened) root.close(); else root.open();
        }
    }
    onOpenedChanged: if (opened) button.hideOwnTooltip()
}
