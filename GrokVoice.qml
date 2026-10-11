import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var store
    readonly property string voiceHome: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME")+"/.local/share")+"/oma-pulse-voice"
    readonly property string script: Qt.resolvedUrl("grok_voice.py").toString().replace("file://", "")
    readonly property bool wakeEnabled: store.ready && store.workspace.voiceEnabled === true
    property string sessionMode: "listen"
    property bool failed: false
    property bool listeningEnabled: false
    property bool configured: false
    property bool ready: false
    property bool overlayVisible: false
    property string phase: "off"
    property string statusText: "Grok live is off"
    property string error: ""
    property string heard: ""
    property int latencyMs: -1
    property bool duplex: false
    property string pendingCall: ""
    property bool stopping: false
    property int retries: 0
    property string settingsMode: "check"
    property string keyToSave: ""
    property string botToSave: ""
    property string defaultBot: ""
    property bool settingsReceived: false
    readonly property bool settingsBusy: settings.running
    readonly property bool canStart: ready && !settingsBusy && !session.running
    function refresh() {
        if(settings.running) return;
        settingsMode="check"; settingsReceived=false; settings.running=true;
    }
    function saveKey(value) {
        if(settings.running || listeningEnabled) return;
        error=""; settingsMode="save-key"; keyToSave=value.trim(); settingsReceived=false; settings.running=true;
    }
    function saveBot(value) {
        if(settings.running) return;
        error=""; settingsMode="save-bot"; botToSave=value.trim(); settingsReceived=false; settings.running=true;
    }
    function control(value) { if(session.running) session.write(JSON.stringify(value)+"\n"); }
    function saveWake(value) {
        if(!store.ready) return;
        store.workspace=Object.assign({},store.workspace,{voiceEnabled:!!value}); store.changed();
    }
    function enableWake() {
        saveWake(true); failed=false;
        if(canStart) startSession("wake");
    }
    function startSession(mode) {
        if(!canStart) { error="Add your xAI key and finish voice setup first."; return; }
        if(store.assistant.busy || store.assistant.recording) {
            // Wake mode simply starts once Pulse is free; only a manual start reports it.
            if(mode !== "wake") { error="Wait for the current Pulse request to finish."; failed=true; }
            return;
        }
        sessionMode=mode;
        error=""; heard=""; latencyMs=-1; duplex=false; failed=false; phase="starting";
        statusText=mode === "wake" ? "Starting Hey Pulse for Grok…" : "Connecting to Grok…";
        listeningEnabled=true; overlayVisible=mode !== "wake"; session.running=true;
    }
    function setEnabled(value) {
        if(value) {
            if(session.running) return;
            saveWake(false);
            startSession("listen");
        } else {
            saveWake(false);
            stopSession("Grok live is off");
        }
    }
    function stopSession(text) {
        listeningEnabled=false;
        control({type:"quit"});
        if(pendingCall) { store.assistant.pendingActions=[]; store.assistant.cancel(); pendingCall=""; }
        phase="off"; statusText=text; overlayVisible=false;
        if(session.running) { stopping=true; stopTimer.restart(); }
    }
    // Ends the live conversation only. Wake mode stays saved, so Hey Pulse rearms
    // once the session exits; while merely armed there is nothing to end.
    function endConversation() {
        if(!wakeEnabled) { setEnabled(false); return; }
        if(overlayVisible) stopSession("Rearming Hey Pulse…");
    }
    // One key for everything, never turning always-on listening off: end the
    // current conversation, start one without the wake phrase, or switch Hey Pulse on.
    function talk() {
        if(overlayVisible) endConversation();
        else if(!wakeEnabled) enableWake();
        else if(session.running) control({type:"wake"});
    }
    function stopSpeaking() { control({type:"stop_speaking"}); }
    // What the shell already holds, so reading it back needs no planner round trip.
    function snapshot(topic) {
        var time=ms => Qt.formatTime(new Date(ms), "h:mm AP");
        if(topic === "calendar") return "Today is "+store.today+".\n"+store.agendaDays.map(d => d.label+" ("+d.date+"):\n"+(d.events.length ? d.events.map(e =>
            "  "+(e.all_day ? "all day" : time(e.start_ms)+" to "+time(e.end_ms))+": "+e.title+(e.location ? " at "+e.location : "")+(e.response && e.response !== "accepted" ? " ("+e.response+")" : "")).join("\n") : "  nothing scheduled")).join("\n");
        if(topic === "tasks") { var open=store.tasks.filter(t => !t.done).slice(0,60); return open.length ? open.map(t => "- "+t.title+(t.due ? " (due "+t.due+")" : "")).join("\n") : "No open tasks."; }
        if(topic === "note") return store.note ? store.note.slice(0,4000) : "Today's note is empty.";
        if(topic === "inbox") return store.newMail.length ? store.newMail.slice(0,15).map(m => "- "+m.creator+": "+m.title+(m.excerpt ? " — "+m.excerpt : "")).join("\n") : "No new mail.";
        return "";
    }
    function acceptTool(result) {
        if(!listeningEnabled) return;
        if(result.query) {
            var text=""; try { text=snapshot(result.query); } catch(e) {}
            control({type:"tool_result",call_id:result.call_id,ok:!!text,text:text || "That information is unavailable right now."}); return;
        }
        if(pendingCall || store.assistant.busy || store.assistant.recording) {
            control({type:"tool_result",call_id:result.call_id,ok:false,text:"Pulse is busy. Try again when the current request finishes."}); return;
        }
        pendingCall=result.call_id;
        // The existing parser, action validation and execution stay authoritative.
        if(!(result.action ? store.assistant.run(result.action) : store.assistant.ask(result.text, false))) {
            control({type:"tool_result",call_id:pendingCall,ok:false,text:"Pulse could not start that request."}); pendingCall="";
        }
    }
    Connections {
        target: root.store.assistant
        function onRequestFinished(text, ok, followUp) {
            if(!root.pendingCall) return;
            root.control({type:"tool_result",call_id:root.pendingCall,ok:ok,text:text || (ok ? "Done." : "The request failed.")});
            root.pendingCall="";
        }
        function onRecordingChanged() {
            if(!root.store.assistant.recording || !root.listeningEnabled) return;
            if(root.wakeEnabled) root.endConversation(); else root.setEnabled(false);
        }
    }
    Process {
        id: settings
        command: [root.voiceHome+"/venv/bin/python",root.script,root.settingsMode]
        stdinEnabled: true
        onStarted: {
            if(root.settingsMode === "save-key") settings.write(JSON.stringify({key:root.keyToSave})+"\n");
            else if(root.settingsMode === "save-bot") settings.write(JSON.stringify({bot:root.botToSave})+"\n");
            root.keyToSave=""; settings.stdinEnabled=false;
        }
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var result=JSON.parse(line); root.settingsReceived=true;
                    if(result.event === "config") { root.configured=result.configured; root.ready=result.ready; root.defaultBot=result.defaultBot || ""; root.error=result.error || ""; }
                    else if(result.event === "error") root.error=result.error;
                } catch(e) { root.error="Could not read Grok setup status."; }
            }
        }
        onExited: function(code) {
            root.keyToSave=""; settings.stdinEnabled=true;
            if(!root.settingsReceived) root.error="Run scripts/setup-grok-voice.py to prepare Grok voice.";
        }
    }
    Process {
        id: session
        command: [root.voiceHome+"/venv/bin/python",root.script,root.sessionMode]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function(line) {
                if(!root.listeningEnabled) return;
                try {
                    var result=JSON.parse(line);
                    if(result.event === "state") {
                        root.phase=result.state; root.statusText=result.text;
                        if(result.state === "armed") { root.retries=0; root.error=""; }
                        root.overlayVisible=["listening","speaking","thinking"].indexOf(result.state)>=0 || (result.state === "starting" && (root.sessionMode !== "wake" || root.overlayVisible));
                    }
                    else if(result.event === "wake") { root.overlayVisible=true; root.heard=""; }
                    else if(result.event === "transcript") { root.heard=result.text; }
                    else if(result.event === "reply") { root.statusText=result.text; }
                    else if(result.event === "latency") root.latencyMs=result.milliseconds;
                    else if(result.event === "audio_mode") root.duplex=result.duplex === true;
                    else if(result.event === "tool_request") root.acceptTool(result);
                    else if(result.event === "ended") { root.setEnabled(false); root.statusText=result.text; }
                    else if(result.event === "error") { root.error=result.error; root.phase="error"; root.statusText=result.error; }
                } catch(e) { root.error="Could not read Grok voice status."; }
            }
        }
        onExited: function(code) {
            stopTimer.stop();
            if(root.pendingCall) { root.store.assistant.pendingActions=[]; root.store.assistant.cancel(); root.pendingCall=""; }
            root.listeningEnabled=false;
            if(code !== 0 && !root.error && !root.stopping) root.error="Grok stopped. Check API credits and try again.";
            root.stopping=false;
            root.failed=!!root.error;
            root.phase=root.error ? "error" : "off";
            if(root.error) root.statusText=root.error;
            root.overlayVisible=false;
        }
    }
    Timer { id: stopTimer; interval: 1500; onTriggered: if(session.running) session.running=false }
    Timer { interval: 200; running: root.wakeEnabled && root.ready && !root.settingsBusy && !session.running && !root.failed; onTriggered: root.startSession("wake") }
    // Always-on listening recovers by itself if the wake session ever dies.
    Timer {
        interval: Math.min(60000, 5000*Math.pow(2, root.retries))
        running: root.wakeEnabled && root.ready && root.failed && !session.running
        onTriggered: { root.retries+=1; root.failed=false; }
    }
    Component.onCompleted: refresh()
}
