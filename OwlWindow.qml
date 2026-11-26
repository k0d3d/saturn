pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
    id: win
    property var screen
    required property var store
    property bool dashboardOpen: false
    property bool commandOpen: false
    property string currentTab: "Workspace"
    readonly property alias dashboard: dashboardWindow
    readonly property alias workspacePanel: dashboardWindow
    readonly property alias timerPopout: focusPopout
    readonly property alias commandPanel: commandWindow
    function open() { commandOpen = false; dashboardOpen = true; }
    function close() { store.flush(); dashboardOpen = false; }
    function openDashboard() { open(); }
    function openCommand() { dashboardOpen = false; commandOpen = true; }
    CommandWindow {
        id: commandWindow; screen: win.screen; store: win.store; visible: win.commandOpen
        onDismissed: win.commandOpen = false
        onWorkspaceRequested: win.open()
    }
    TimerPopout {
        id: focusPopout; screen: win.screen; store: win.store
        visible: win.store.focusState.running && !win.dashboardOpen && !win.commandOpen
        onOpenRequested: win.open()
    }
    Dashboard {
        id: dashboardWindow; screen: win.screen; store: win.store; visible: win.dashboardOpen
        onDismissed: win.close()
    }
}
