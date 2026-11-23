function action(kind, value, number) {
    return {kind:kind, value:value || "", number:number || 0, task_id:""};
}
function confirmation(a) {
    switch(a.kind) {
    case "show_pulse": return a.value === "close" ? "Saturn closed." : (a.value === "workspace" ? "Workspace" : a.value.charAt(0).toUpperCase()+a.value.slice(1))+" open.";
    case "start_focus": return a.number+" minute timer started.";
    case "pause_focus": return "Timer paused.";
    case "resume_focus": return "Timer resumed.";
    case "set_volume": return "Volume at "+a.number+" percent.";
    case "mute_audio": return a.value === "on" ? "Audio muted." : "Audio restored.";
    case "switch_workspace": return "Workspace "+a.number+".";
    case "media_control": return ({play:"Playing.",pause:"Playback paused.",next:"Next track.",previous:"Previous track."})[a.value] || "Done.";
    case "window_control": return ({fullscreen:"Full screen toggled.",float:"Floating toggled.",close:"Window closed."})[a.value] || "Window focused.";
    case "move_window": return "Moved to workspace "+a.number+".";
    case "screenshot": return "Screenshot tool open.";
    case "lock_screen": return "Locked.";
    case "set_brightness": return "Brightness at "+a.number+" percent.";
    case "type_text": return "Typed.";
    case "next_wallpaper": return "Wallpaper changed.";
    case "open_app": return "Application launched.";
    case "append_note": return "Note saved.";
    case "add_task": return "Task added.";
    default: return "";
    }
}
function parse(question, today) {
    var text = String(question).trim().replace(/[.!?]$/, ""), match;
    text = text.replace(/^(?:(?:can|could|would) you\s+)?(?:please\s+)?/i, "").replace(/,?\s+please$/i, "");
    text = text.replace(/^(?:hey\s+)?saturn[,\s]+/i, "");
    match = text.match(/^(?:open|show|go to)\s+(?:(?:my|the|oma|saturn)\s+)?(saturn|workspace|messages|assistant|connections|insights|notepad|notes|dashboard)$/i);
    if (match) return action("show_pulse",/^(saturn|dashboard|notepad|notes)$/i.test(match[1]) ? "workspace" : match[1].toLowerCase());
    if (/^(?:close|hide|dismiss)\s+(?:oma\s+)?saturn$/i.test(text)) return action("show_pulse","close");
    if (/^(?:mute|unmute)(?:\s+(?:the\s+)?(?:sound|audio|volume))?$/i.test(text)) return action("mute_audio",/^unmute/i.test(text) ? "off" : "on");
    match = text.match(/^(?:switch to|go to|show)\s+workspace\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)$/i);
    if (match) return action("switch_workspace","",spokenNumber(match[1]));
    if (/^(?:play|resume)(?:\s+(?:the\s+)?(?:music|media|playback))$/i.test(text)) return action("media_control","play");
    if (/^(?:pause|stop)(?:\s+(?:the\s+)?(?:music|media|playback))$/i.test(text)) return action("media_control","pause");
    if (/^(?:next|skip)(?:\s+(?:track|song))?$/i.test(text)) return action("media_control","next");
    if (/^(?:previous|last)\s+(?:track|song)$/i.test(text)) return action("media_control","previous");
    if (/^(?:toggle\s+)?full\s*screen$/i.test(text)) return action("window_control","fullscreen");
    match = text.match(/^(?:focus|select)(?:\s+(?:the\s+)?window)?\s+(?:to\s+the\s+)?(left|right|up|down)$/i);
    if(match) return action("window_control",match[1].toLowerCase());
    // Normalize spoken quantities only in commands, never task/note content.
    if (!/\b(note|task)\b/i.test(text) && /^(start|set|make|create|volume)\b/i.test(text)) text=text.replace(/\b(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[- ](?:one|two|three|four|five|six|seven|eight|nine))?\b|\b(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|hundred)\b/gi, n=>String(spokenNumber(n)));
    match = text.match(/^(?:start|set|make|create)\s+(?:me\s+)?(?:a\s+)?(\d+)\s*-?\s*(minutes?|mins?|m|hours?|hrs?|h)\s+(?:of\s+)?(?:focus(?:\s+session)?|timer)(?:\s+(?:called|for)\s+(.+))?$/i);
    if (!match) match = text.match(/^(?:start|set|make|create)\s+(?:me\s+)?(?:a\s+)?(?:timer|focus(?:\s+session)?)\s+(?:for\s+)?(\d+)\s*(minutes?|mins?|m|hours?|hrs?|h)(?:\s+(?:called|for)\s+(.+))?$/i);
    if (match) return action("start_focus",match[3] || "Open focus",Number(match[1]) * (/^h/i.test(match[2]) ? 60 : 1));
    if (/^start\s+(?:a\s+)?(?:focus|focus session|timer)$/i.test(text)) return action("start_focus","Open focus",25);

    if (/^pause\s+(?:the\s+)?(?:focus|timer|focus timer)$/i.test(text)) return action("pause_focus");
    if (/^resume\s+(?:the\s+)?(?:focus|timer|focus timer)$/i.test(text)) return action("resume_focus");
    match = text.match(/^(?:set\s+)?(?:the\s+)?volume\s+(?:to\s+)?(\d+)\s*(?:%|percent)?$/i);
    if (match) return action("set_volume","",Number(match[1]));
    match = text.match(/^(?:add\s+(?:a\s+)?(?:todoist\s+)?task\s*:?|todo:)\s+(.+)$/i);
    if (match) return action("add_task",match[1]);
    match = text.match(/^(?:note:|(?:take|make|add)\s+(?:a\s+)?note\s*:?|note that)\s*(.+)$/i);
    if (match) return action("append_note",match[1]);
    match = text.match(/^(?:find|search for)\s+files?\s+(?:named\s+)?(.+)$/i);
    if (match) return action("search_files",match[1]);
    match = text.match(/^show\s+(today|tomorrow)(?:[’']s)?(?:\s+calendar)?$/i);
    if (match) {
        var date = new Date(today + "T12:00:00Z");
        if (match[1].toLowerCase() === "tomorrow") date.setUTCDate(date.getUTCDate()+1);
        return action("show_day",date.toISOString().slice(0,10));
    }
    match = text.match(/^open\s+(?:(?:my|the)\s+)?(browser|terminal|file manager|files|hey|todoist|calendar)$/i);
    if (match) return action("open_app",match[1].toLowerCase() === "file manager" ? "files" : match[1].toLowerCase());
    return null;
}
function spokenNumber(value) {
    if (/^\d+$/.test(value)) return Number(value);
    var words={one:1,two:2,three:3,four:4,five:5,six:6,seven:7,eight:8,nine:9,ten:10,eleven:11,twelve:12,fifteen:15,twenty:20,thirty:30,forty:40,fifty:50,sixty:60,seventy:70,eighty:80,ninety:90,hundred:100};
    return String(value).toLowerCase().split(/[ -]+/).reduce((sum,w)=>sum+(words[w] || 0),0);
}
