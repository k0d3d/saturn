// Local preview heuristics only. Rules never delete or mark messages read.
function key(row) { return String(row.source) + ":" + String(row.id); }
function sourceEnabled(sources, name) {
    return name === "texts" ? !sources || sources.texts !== false : !!sources && sources[name] === true;
}
function sourceRows(rows, sources) {
    return rows.filter(function(row) {
        var name=row.source === "blip" ? "texts" : row.source === "beeper" ? (/slack/i.test(row.network || "") ? "slack" : "beeper") : "unknown";
        return name !== "unknown" && sourceEnabled(sources,name);
    });
}
function reason(row, overrides, keepAlerts) {
    var override = overrides && overrides[key(row)];
    if (override === "keep") return "";
    if (override === "hide") return "Hidden by you";
    // Work/chat networks are kept unless the user explicitly hides a thread.
    var isText = row.source === "blip" || /\b(sms|rcs|imessage|google messages|google voice)\b/i.test(row.network || "");
    if (!isText) return "";
    var text = String(row.preview || "").normalize("NFKC").replace(/[\u200b-\u200d\ufeff]/g, "").replace(/[’‘]/g,"'").replace(/[“”]/g,'"').toLowerCase();
    var shortCode = /^\d{3,6}$/.test(String(row.id || "").replace(/^(?:sms|imessage)[;:-]+/i,"").replace(/[\s()-]/g,""));
    var optOut = /\b(?:reply|text|txt|send|respond)\s*(?:with\s+)?["']?stop\b|\bstop["']?\s*(?:2|to)\s*(?:stop|end|quit|cancel|unsubscribe)\b|\bstop\s+(?:end|quit)\b|\b(?:unsubscribe|opt[ -]?out)\b/.test(text);
    var code = /\b(?:verification|security|authentication|one[ -]?time|sign[ -]?in|login|access)\s+(?:code|pin)\b|\b(?:code|pin)\s+(?:is\s*)?[:=-]?\s*\d{4,8}\b/.test(text);
    var alert = code || /\b(?:appointment|reservation|delivery|shipment|payment|transaction|flight)\s+(?:reminder|confirmation|confirmed|scheduled|cancelled|delayed|alert|notice)\b|\byour\s+(?:package|shipment|prescription|payment|order|pickup|appointment|reservation|flight)\s+(?:#?\d+|is|was|has|will|for|at)\b|\b(?:tracking number|fraud alert|payment received|order confirmed|order shipped)\b/.test(text);
    var discount = /\b\d{1,3}\s*%\s*off\b|\b(?:coupon|promo code|discount code|buy one get|bogo)\b|\b(?:save|take|get)\s+(?:up to\s+)?[$£€]\s*\d+|\buse\s+(?:the\s+)?code\b/.test(text);
    var shopping = /\b(?:shop now|shop the|shop our|shop all|buy now|flash sale|clearance sale|sale ends|exclusive offer|limited[ -]time offer)\b/.test(text);
    var urgency = /\b(?:ends tonight|ends today|last chance|today only|limited time|this weekend)\b/.test(text);
    var link = /https?:\/\/|\bwww\.|\b[a-z0-9-]+\.(?:com|co|io|me|ly|us|shop|sale|link|today|xyz)\//.test(text);
    var campaign = /\b(?:free shipping|free gift|new arrivals|back in stock|early access|members? only|vip access|shop and save|claim your|unlock your|last day|final hours|selling fast|while supplies last|limited stock|just dropped)\b/.test(text);
    var offer = /\b(?:sale|deals?|offers?|discount|save|savings|bonus|reward|rewards|exclusive)\b/.test(text);
    var brandPrefix = /^[\w &.'-]{2,35}:\s/.test(text);
    var personal = /^(?:i (?:got|found|bought|think|saw|was|am|have)|can you|did you|do you|what do you)\b/.test(text);
    var promotion = shopping || (discount && (optOut || link || shortCode || urgency)) || (optOut && urgency)
        || (!personal && link && (campaign || (offer && (brandPrefix || urgency))));
    // Preserve clear service alerts even when they include STOP instructions.
    if (keepAlerts !== false && alert && !promotion && !discount) return "";
    if (promotion) return "Likely promotion";
    if (keepAlerts === false && (alert || shortCode || optOut)) return "Automated text";
    return "";
}
function select(rows, overrides, keepAlerts) {
    return rows.filter(function(row) { return !reason(row, overrides, keepAlerts); });
}
