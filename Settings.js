// Config for features that do not have a settings screen yet. Kept in
// workspace.json so both the live shell and offline scripts read the same
// values. Unknown keys are dropped on write; defaults fill anything missing.
function freshSettings() {
    return {llm: {enabled: true, model: "opencode/deepseek-v4.1-flash-free",
                  hours: [9, 18], batch: 20, timeout: 120, prompt: ""}};
}
function normaliseSettings(raw) {
    var base = freshSettings();
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return base;
    var value = raw.llm && typeof raw.llm === "object" && !Array.isArray(raw.llm) ? raw.llm : {};
    var hours = base.llm.hours;
    if (Array.isArray(value.hours) && value.hours.every(function(h) {
            return typeof h === "number" && isFinite(h) && Math.floor(h) === h && h >= 0 && h <= 23;
        })) {
        hours = value.hours.filter(function(h, i) { return value.hours.indexOf(h) === i; });
    }
    return {llm: {
        enabled: typeof value.enabled === "boolean" ? value.enabled : base.llm.enabled,
        model: typeof value.model === "string" && value.model.trim().length > 0 && value.model.length <= 120
               ? value.model.trim() : base.llm.model,
        hours: hours,
        batch: typeof value.batch === "number" && isFinite(value.batch) && value.batch >= 1 && value.batch <= 100
               ? Math.floor(value.batch) : base.llm.batch,
        timeout: typeof value.timeout === "number" && isFinite(value.timeout) && value.timeout >= 10 && value.timeout <= 600
                 ? Math.floor(value.timeout) : base.llm.timeout,
        prompt: typeof value.prompt === "string" ? value.prompt.slice(0, 2000) : base.llm.prompt,
    }};
}
var fresh = freshSettings;
var normalise = normaliseSettings;
