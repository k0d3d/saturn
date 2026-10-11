import QtQuick
import Quickshell
import Quickshell.Io
import "MessageRules.js" as Rules

Item {
    id: root
    required property var store
    readonly property bool keyOnly: store.workspace.messageKeyOnly !== false
    readonly property bool keepAlerts: store.workspace.messageKeepAlerts === true
    readonly property var rules: store.workspace.messageRules || ({})
    readonly property var sources: store.workspace.messageSources || ({})
    readonly property bool textsEnabled: Rules.sourceEnabled(sources,"texts")
    readonly property bool slackEnabled: Rules.sourceEnabled(sources,"slack")
    readonly property bool beeperEnabled: Rules.sourceEnabled(sources,"beeper")
    readonly property bool anySource: textsEnabled || slackEnabled || beeperEnabled
    readonly property string sourceSummary: [textsEnabled ? "Texts" : "",slackEnabled ? "Slack" : "",beeperEnabled ? "Other Beeper" : ""].filter(s => !!s).join(" · ") || "No sources selected"
    function sourceEnabled(name) { return Rules.sourceEnabled(sources,name); }
    function setSource(name, value) {
        if(["texts","slack","beeper"].indexOf(name)<0) return;
        var next=Object.assign({},sources); next[name]=!!value;
        setPreference("messageSources",next);
    }
    onSourcesChanged: if(store.ready) { refreshPending=true; retry.restart(); }
    function setPreference(name, value) {
        if (!store.ready) return;
        var change={}; change[name]=value;
        store.workspace=Object.assign({},store.workspace,change); store.changed();
    }
    function setKeyOnly(value) { setPreference("messageKeyOnly", !!value); }
    function setKeepAlerts(value) { setPreference("messageKeepAlerts", !!value); }
    function setRule(row, value) {
        if (["keep","hide","auto"].indexOf(value)<0) return;
        var next=Object.assign({},rules);
        if(value === "auto") delete next[Rules.key(row)]; else next[Rules.key(row)]=value;
        setPreference("messageRules",next);
    }
    function ruleFor(row) { return rules[Rules.key(row)] || "auto"; }
    function hiddenReason(row) { return Rules.reason(row,rules,keepAlerts); }
    property var viewers: []
    readonly property bool active: viewers.length > 0
    function setViewActive(view, shown) {
        var next=viewers.filter(v => v !== view);
        if(shown) next.push(view);
        viewers=next;
    }
    property var blip: ({connected: false, rows: [], error: ""})
    property var beeper: ({connected: false, rows: [], error: ""})
    property bool beeperConfigured: false
    property string error: ""
    property double updated: 0
    property var payload: ({})
    property string operation: ""
    property bool received: false
    property bool refreshPending: false
    property var pendingRead: null
    readonly property bool busy: worker.running
    readonly property var allRows: Rules.sourceRows(blip.rows.concat(beeper.rows),sources).sort((a,b) => String(b.timestamp).localeCompare(String(a.timestamp)))
    readonly property var keyRows: Rules.select(allRows, rules, keepAlerts)
    readonly property int hiddenCount: allRows.length-keyRows.length
    readonly property var rows: keyOnly ? keyRows : allRows
    readonly property int unread: rows.reduce((sum,row) => sum + row.unread, 0)
    signal opened()
    function send(request) {
        if (busy) return;
        payload=request; operation=request.action; received=false; error="";
        worker.stdinEnabled=true; worker.running=true;
    }
    function refresh() {
        if(busy) { refreshPending=true; return; }
        refreshPending=false;
        send({action:"sync",blipEnabled:textsEnabled,beeperEnabled:slackEnabled || beeperEnabled});
    }
    function connectToken(token) { send({action:"connect",token:token}); }
    function disconnectAccount() { send({action:"disconnect"}); }
    function openConversation(row) { send({action:"open",source:row.source,id:row.id}); }
    function markRead(row) {
        if(busy) return;
        pendingRead={source:row.source,id:row.id,timestamp:row.timestamp,messageId:row.messageId || ""};
        send(Object.assign({action:"read"},pendingRead));
    }
    onActiveChanged: if(active && Date.now()-updated > 15000) refresh()
    Process {
        id: worker
        command: ["timeout","50s","python3",Qt.resolvedUrl("messages.py").toString().replace("file://", "")]
        onStarted: { write(JSON.stringify(root.payload)+"\n"); stdinEnabled=false; root.payload=({}); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var r=JSON.parse(text); root.received=true;
                    if(!r.ok) { root.error=r.error; return; }
                    if(r.beeperConfigured !== undefined) root.beeperConfigured=r.beeperConfigured;
                    if(root.operation === "sync") { root.blip=r.blip; root.beeper=r.beeper; root.updated=Date.now(); }
                    if(root.operation === "disconnect") root.beeper=({connected:false,rows:[],error:"Beeper disconnected."});
                    if(root.operation === "open") root.opened();
                    if(root.operation === "read" && r.remove && root.pendingRead) {
                        var selected=root.pendingRead;
                        var feed=selected.source === "blip" ? root.blip : root.beeper;
                        var next=Object.assign({},feed,{rows:feed.rows.filter(row => row.id !== selected.id || row.timestamp !== selected.timestamp)});
                        if(selected.source === "blip") root.blip=next; else root.beeper=next;
                    }
                } catch(e) { root.error="Could not read message connection response."; }
            }
        }
        onExited: function(code) {
            root.payload=({});
            root.pendingRead=null;
            if(!root.received) root.error="Message connection timed out or stopped. Try refreshing.";
            if(root.refreshPending || (root.received && !root.error && ["connect","disconnect","read"].indexOf(root.operation)>=0)) retry.restart();
        }
    }
    Timer { id: retry; interval: 100; onTriggered: root.refresh() }
    Timer { interval: 30000; repeat: true; running: root.active; onTriggered: root.refresh() }
}
