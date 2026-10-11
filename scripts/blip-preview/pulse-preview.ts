// Rebuild: bun build pulse-preview.ts --target browser --format esm --outfile PulsePreview.mjs
// Separate preview and per-thread read opt-ins; never enables sending.
export function enabled(config: string): boolean {
  return /^\s*pulse_previews\s*=\s*['"]?(on|true|1|yes)['"]?\s*(?:#.*)?$/mi.test(config);
}

export function readEnabled(config: string): boolean {
  return /^\s*pulse_mark_read\s*=\s*['"]?(on|true|1|yes)['"]?\s*(?:#.*)?$/mi.test(config);
}

export function readRequest(allowed: boolean, online: boolean, threads: any[], chat: string, seen: string): string {
  if (!allowed) return 'Enable pulse_mark_read=on in Blip’s bridge.conf.';
  if (!online) return 'Blip’s Mac bridge is offline. Try again when connected.';
  const thread = threads.find(t => t && t.chat === chat);
  if (!thread) return 'Conversation unavailable. Refresh and try again.';
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(seen) || !Number.isFinite(Date.parse(seen))) return 'Invalid preview timestamp.';
  if (thread.last_ts !== seen) return 'This conversation changed. Refresh before marking it read.';
  return '';
}

export function snapshot(allowed: boolean, online: boolean, threads: any[]): object {
  if (!allowed) return { enabled: false, online, rows: [] };
  const rows = threads.filter(t => t && typeof t.chat === 'string' && t.chat && Number(t.unread) > 0)
    .map(t => ({ id: t.chat, source: 'blip', network: 'Blip · ' + (t.service || 'Messages'),
      name: String(t.name || t.chat), preview: String(t.last_text || 'Open conversation').slice(0, 500),
      timestamp: String(t.last_ts || ''), unread: Math.max(1, Math.floor(Number(t.unread))) }));
  return { enabled: true, online, rows };
}
