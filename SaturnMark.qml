pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// The brand mark split along the original SVG's paint order: the back of the
// ring sits behind the planet, the front bands sit above it, and the five star
// dots twinkle independently. Qt renders SVG statically, so every bit of motion
// happens here on the QML items instead of inside the vector file.
Item {
    id: mark
    property bool active: false
    property real size: 46
    implicitWidth: mark.size
    implicitHeight: mark.size

    Theme { id: theme }

    // Quiet halo that lifts a little while a focus session is running.
    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: mark.size * 1.1; height: mark.size * 1.1
        radius: width / 2
        color: theme.accent
        opacity: 0.045
    }
    Rectangle {
        anchors.centerIn: parent
        width: mark.size * 1.1; height: mark.size * 1.1
        radius: width / 2
        color: theme.accent
        opacity: mark.active ? 0.07 : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    }
    SequentialAnimation {
        loops: Animation.Infinite
        running: true
        NumberAnimation { target: halo; property: "opacity"; from: 0.035; to: 0.085; duration: Style.duration(1900); easing.type: Easing.InOutSine }
        NumberAnimation { target: halo; property: "opacity"; from: 0.085; to: 0.035; duration: Style.duration(1900); easing.type: Easing.InOutSine }
    }

    Image {
        id: backRing
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/saturn-back.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: mark.size * 2; sourceSize.height: mark.size * 2
        mipmap: true
        transformOrigin: Item.Center
    }
    SequentialAnimation {
        loops: Animation.Infinite
        running: true
        NumberAnimation { target: backRing; property: "rotation"; from: -8; to: 8; duration: Style.duration(3400); easing.type: Easing.InOutSine }
        NumberAnimation { target: backRing; property: "rotation"; from: 8; to: -8; duration: Style.duration(3400); easing.type: Easing.InOutSine }
    }

    Image {
        id: planet
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/saturn-planet.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: mark.size * 2; sourceSize.height: mark.size * 2
        mipmap: true
        transformOrigin: Item.Center
    }
    SequentialAnimation {
        loops: Animation.Infinite
        running: true
        NumberAnimation { target: planet; property: "rotation"; from: 5; to: -5; duration: Style.duration(3700); easing.type: Easing.InOutSine }
        NumberAnimation { target: planet; property: "rotation"; from: -5; to: 5; duration: Style.duration(3700); easing.type: Easing.InOutSine }
    }

    Image {
        id: frontRing
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/saturn-ring.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: mark.size * 2; sourceSize.height: mark.size * 2
        mipmap: true
        transformOrigin: Item.Center
    }
    // Counter-rotates against the back band on a shorter cycle, so the ring
    // shimmers as it tilts instead of moving as one flat cut-out.
    SequentialAnimation {
        loops: Animation.Infinite
        running: true
        NumberAnimation { target: frontRing; property: "rotation"; from: 8; to: -8; duration: Style.duration(2600); easing.type: Easing.InOutSine }
        NumberAnimation { target: frontRing; property: "rotation"; from: -8; to: 8; duration: Style.duration(2600); easing.type: Easing.InOutSine }
    }

    Repeater {
        model: 5
        Image {
            id: star
            required property int index
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/saturn-star-" + (index + 1) + ".svg")
            fillMode: Image.PreserveAspectFit
            sourceSize.width: mark.size * 2; sourceSize.height: mark.size * 2
            mipmap: true
            opacity: 0.3
            SequentialAnimation {
                loops: Animation.Infinite
                running: true
                NumberAnimation { target: star; property: "opacity"; from: 0.25; to: 1; duration: Style.duration(650 + index * 185); easing.type: Easing.InOutQuad }
                NumberAnimation { target: star; property: "opacity"; from: 1; to: 0.25; duration: Style.duration(650 + index * 185); easing.type: Easing.InOutQuad }
            }
        }
    }

    SequentialAnimation {
        loops: Animation.Infinite
        running: true
        NumberAnimation { target: mark; property: "scale"; from: 0.985; to: 1.015; duration: Style.duration(2100); easing.type: Easing.InOutSine }
        NumberAnimation { target: mark; property: "scale"; from: 1.015; to: 0.985; duration: Style.duration(2100); easing.type: Easing.InOutSine }
    }
}
