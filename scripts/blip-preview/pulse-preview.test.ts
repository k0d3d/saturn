import { test, expect } from 'bun:test';
import { enabled, snapshot, readEnabled, readRequest } from './pulse-preview';

test('preview export requires its own explicit opt-in', () => {
  for (const conf of ['', 'automation=on', 'pulse_previews=off', '# pulse_previews=on', 'pulse_previews=onward']) expect(enabled(conf)).toBe(false);
  expect(enabled('pulse_previews=on')).toBe(true);
  expect(enabled('pulse_previews="yes" # personal integration')).toBe(true);
  expect(snapshot(false, true, [{chat:'+15551234567',last_text:'Private',unread:1}])).toEqual({enabled:false,online:true,rows:[]});
});

test('mark-read opt-in is independent of previews and automation', () => {
  expect(readEnabled('pulse_previews=on\nautomation=on')).toBe(false);
  expect(readEnabled('pulse_mark_read=on')).toBe(true);
  expect(readEnabled('# pulse_mark_read=on')).toBe(false);
  expect(readEnabled('pulse_mark_read=onward')).toBe(false);
});

test('read action is scoped to the exact current conversation preview', () => {
  const seen='2026-10-09T10:00:00Z';
  const threads=[{chat:'+15551234567',last_ts:seen,unread:2}];
  expect(readRequest(true,true,threads,'+15551234567',seen)).toBe('');
  expect(readRequest(false,true,threads,'+15551234567',seen)).toContain('pulse_mark_read');
  expect(readRequest(true,false,threads,'+15551234567',seen)).toContain('offline');
  expect(readRequest(true,true,threads,'other',seen)).toContain('unavailable');
  expect(readRequest(true,true,threads,'+15551234567','2026-10-09T09:00:00Z')).toContain('changed');
  expect(readRequest(true,true,threads,'+15551234567','')).toContain('timestamp');
  expect(threads[0].unread).toBe(2);
});

test('exports only unread preview fields without mutating read state', () => {
  const threads = [{chat:'+15551234567',name:'Sample',last_text:'Hello',last_ts:'2026-10-09T10:00:00Z',unread:2,guid:'private',participants:['hidden']}, {chat:'read-chat',unread:0}];
  const before = JSON.stringify(threads);
  const result: any = snapshot(true, false, threads);
  expect(result.rows).toEqual([{id:'+15551234567',source:'blip',network:'Blip · Messages',name:'Sample',preview:'Hello',timestamp:'2026-10-09T10:00:00Z',unread:2}]);
  expect(result.online).toBe(false);
  expect(JSON.stringify(threads)).toBe(before);
});
