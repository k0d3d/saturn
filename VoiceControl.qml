import QtQuick

// Compatibility facade: Hey Saturn now wakes Grok. No local TTS process is used.
Item {
    required property var store
    readonly property bool listeningEnabled: store.grokVoice.wakeEnabled
    readonly property bool spokenReplies: true
    readonly property string phase: store.grokVoice.phase
    readonly property string statusText: store.grokVoice.statusText
    readonly property string error: store.grokVoice.error
    readonly property string heard: store.grokVoice.heard
    readonly property bool overlayVisible: false
    function setEnabled(value) { if(value) store.grokVoice.enableWake(); else store.grokVoice.setEnabled(false); }
    function stopSpeaking() { store.grokVoice.endConversation(); }
}
