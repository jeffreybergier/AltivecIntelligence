'use strict';

// A deliberately narrow XML plist reader. Keep source offsets so updating a
// top-level string never reformats or rewrites unrelated plist content.
function parse(text) {
  let offset = 0;
  function fail() { throw new Error('unsupported or malformed XML plist (use UTF-8 XML with a root dict)'); }
  function whitespace() {
    while (true) {
      const match = /^(?:\s+|<!--[\s\S]*?-->)/.exec(text.slice(offset));
      if (!match) return;
      if (match[0].startsWith('<!--') && match[0].slice(4, -3).includes('--')) fail();
      offset += match[0].length;
    }
  }
  function literal(value) {
    whitespace();
    if (!text.startsWith(value, offset)) fail();
    offset += value.length;
  }
  function decode(value) {
    if (value.includes(']]>')) fail();
    if (/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value) || /&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[\da-fA-F]+;)/.test(value)) fail();
    return value.replace(/&([^;]+);/g, (_, entity) => {
      const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
      if (entities[entity]) return entities[entity];
      const code = entity.startsWith('#x') ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
      if (!Number.isInteger(code) || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) || (code < 32 && ![9, 10, 13].includes(code))) fail();
      return String.fromCodePoint(code);
    });
  }
  function value() {
    whitespace();
    const open = /^<(dict|array|string|key|integer|real|date|data|true|false)\s*(\/?)>/.exec(text.slice(offset));
    if (!open) fail();
    offset += open[0].length;
    const kind = open[1], start = offset;
    if (open[2]) {
      if (['integer', 'real', 'date'].includes(kind)) fail();
      return { kind, value: kind === 'dict' ? new Map() : '', start, end: start, empty: true };
    }
    if (kind === 'dict' || kind === 'array') {
      const entries = kind === 'dict' ? new Map() : [];
      while (true) {
        whitespace();
        if (text.startsWith(`</${kind}>`, offset)) break;
        const item = value();
        if (kind === 'dict') {
          if (item.kind !== 'key' || entries.has(item.value)) fail();
          const child = value();
          if (child.kind === 'key') fail();
          entries.set(item.value, child);
        } else {
          if (item.kind === 'key') fail();
          entries.push(item);
        }
      }
      literal(`</${kind}>`);
      return { kind, value: entries };
    }
    const end = text.indexOf('<', offset);
    if (end < 0) fail();
    const content = decode(text.slice(offset, end));
    offset = end;
    literal(`</${kind}>`);
    if (kind === 'integer' && !/^[+-]?\d+$/.test(content.trim())) fail();
    if (kind === 'real' && !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(content.trim())) fail();
    if (kind === 'date' && (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(content.trim()) || Number.isNaN(Date.parse(content.trim())))) fail();
    if (kind === 'data' && !/^[\sA-Za-z0-9+/]*={0,2}\s*$/.test(content)) fail();
    if (['true', 'false'].includes(kind) && content.trim()) fail();
    return { kind, value: content, start, end };
  }
  whitespace();
  const declaration = /^<\?xml\s+version="1\.0"(?:\s+encoding="UTF-8")?\s*\?>/i.exec(text.slice(offset));
  if (declaration) offset += declaration[0].length;
  whitespace();
  const doctype = /^<!DOCTYPE plist PUBLIC "-\/\/Apple(?: Computer)?\/\/DTD PLIST 1\.0\/\/EN" "https?:\/\/www\.apple\.com\/DTDs\/PropertyList-1\.0\.dtd"\s*>/.exec(text.slice(offset));
  if (doctype) offset += doctype[0].length;
  literal('<plist version="1.0">');
  const root = value();
  literal('</plist>');
  whitespace();
  if (root.kind !== 'dict' || offset !== text.length) fail();
  return root.value;
}

function inspect(text, keys, replacement) {
  const dict = parse(text);
  const edits = keys.map(key => {
    const node = dict.get(key);
    if (!node || node.kind !== 'string' || node.empty) throw new Error(`missing or unsupported top-level string key: ${key}`);
    return node;
  });
  let updated = text;
  if (replacement !== undefined) {
    for (const node of [...edits].sort((a, b) => b.start - a.start)) {
      updated = updated.slice(0, node.start) + replacement + updated.slice(node.end);
    }
  }
  return { values: edits.map(node => node.value), updated };
}
module.exports = { inspect };
