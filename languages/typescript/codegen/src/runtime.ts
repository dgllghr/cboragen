// === Runtime ===

const _te = new TextEncoder();
const _td = new TextDecoder();

// --- Encoder state ---
let _b = new Uint8Array(256);
let _v = new DataView(_b.buffer);
let _p = 0;

function _grow(n: number): void {
  if (_p + n <= _b.length) return;
  let c = _b.length;
  while (c < _p + n) c *= 2;
  const nb = new Uint8Array(c);
  nb.set(_b);
  _b = nb;
  _v = new DataView(_b.buffer);
}

function _wb(byte: number): void { _grow(1); _b[_p++] = byte; }
function _w16(val: number): void { _grow(2); _v.setUint16(_p, val); _p += 2; }
function _w32(val: number): void { _grow(4); _v.setUint32(_p, val); _p += 4; }
function _w64(val: bigint): void { _grow(8); _v.setBigUint64(_p, val); _p += 8; }

function _eMajLen(base: number, n: number | bigint): void {
  const v = typeof n === "bigint" ? n : BigInt(n);
  if (v <= 23n) { _wb(base | Number(v)); }
  else if (v <= 0xffn) { _wb(base | 24); _wb(Number(v)); }
  else if (v <= 0xffffn) { _wb(base | 25); _w16(Number(v)); }
  else if (v <= 0xffffffffn) { _wb(base | 26); _w32(Number(v)); }
  else { _wb(base | 27); _w64(v); }
}

function _eBool(v: boolean): void { _wb(v ? 0xf5 : 0xf4); }
function _eNull(): void { _wb(0xf6); }

function _eU8(v: number): void { _wb(0x18); _wb(v); }
function _eU16(v: number): void { _wb(0x19); _w16(v); }
function _eU32(v: number): void { _wb(0x1a); _w32(v); }
function _eU64(v: bigint): void { _wb(0x1b); _w64(v); }

function _eI8(v: number): void {
  if (v >= 0) { _wb(0x18); _wb(v); }
  else { _wb(0x38); _wb(-1 - v); }
}
function _eI16(v: number): void {
  if (v >= 0) { _wb(0x19); _w16(v); }
  else { _wb(0x39); _w16(-1 - v); }
}
function _eI32(v: number): void {
  if (v >= 0) { _wb(0x1a); _w32(v); }
  else { _wb(0x3a); _w32(-1 - v); }
}
function _eI64(v: bigint): void {
  if (v >= 0n) { _wb(0x1b); _w64(v); }
  else { _wb(0x3b); _w64(-1n - v); }
}

function _eUvar(v: bigint): void { _eMajLen(0x00, v); }
function _eIvar(v: bigint): void {
  if (v >= 0n) { _eMajLen(0x00, v); }
  else { _eMajLen(0x20, -1n - v); }
}

function _eF16(v: number): void { _wb(0xf9); _grow(2); _v.setFloat16(_p, v); _p += 2; }
function _eF32(v: number): void { _wb(0xfa); _grow(4); _v.setFloat32(_p, v); _p += 4; }
function _eF64(v: number): void { _wb(0xfb); _grow(8); _v.setFloat64(_p, v); _p += 8; }

function _eStr(v: string): void {
  const enc = _te.encode(v);
  _eMajLen(0x60, enc.length);
  _grow(enc.length);
  _b.set(enc, _p);
  _p += enc.length;
}

function _eBytes(v: Uint8Array): void {
  _eMajLen(0x40, v.length);
  _grow(v.length);
  _b.set(v, _p);
  _p += v.length;
}

function _eArrHdr(len: number): void { _eMajLen(0x80, len); }
function _eTagHdr(tag: number): void { _eMajLen(0xc0, tag); }

function _reset(): void { _p = 0; }
function _finish(): Uint8Array { const r = _b.slice(0, _p); _p = 0; return r; }

// --- Decoder state ---
let _db: Uint8Array;
let _dv: DataView;
let _dp: number;

function _dInit(data: Uint8Array): void {
  _db = data; _dv = new DataView(data.buffer, data.byteOffset, data.byteLength); _dp = 0;
}

function _rb(): number { return _db[_dp++]; }
function _r16(): number { const v = _dv.getUint16(_dp); _dp += 2; return v; }
function _r32(): number { const v = _dv.getUint32(_dp); _dp += 4; return v; }
function _r64(): bigint { const v = _dv.getBigUint64(_dp); _dp += 8; return v; }

function _dBool(): boolean {
  const b = _rb();
  if (b === 0xf5) return true;
  if (b === 0xf4) return false;
  throw new Error("expected bool");
}

function _dU8(): number { if (_rb() !== 0x18) throw new Error("expected u8"); return _rb(); }
function _dU16(): number { if (_rb() !== 0x19) throw new Error("expected u16"); return _r16(); }
function _dU32(): number { if (_rb() !== 0x1a) throw new Error("expected u32"); return _r32(); }
function _dU64(): bigint { if (_rb() !== 0x1b) throw new Error("expected u64"); return _r64(); }

function _dI8(): number {
  const b = _rb();
  if (b === 0x18) return _rb();
  if (b === 0x38) return -1 - _rb();
  throw new Error("expected i8");
}
function _dI16(): number {
  const b = _rb();
  if (b === 0x19) return _r16();
  if (b === 0x39) return -1 - _r16();
  throw new Error("expected i16");
}
function _dI32(): number {
  const b = _rb();
  if (b === 0x1a) return _r32();
  if (b === 0x3a) return -1 - _r32();
  throw new Error("expected i32");
}
function _dI64(): bigint {
  const b = _rb();
  if (b === 0x1b) return _r64();
  if (b === 0x3b) return -1n - _r64();
  throw new Error("expected i64");
}

function _dMajLen(expectedMajor: number): number {
  const b = _rb();
  const maj = b >> 5;
  if (maj !== expectedMajor) throw new Error("unexpected major type " + maj);
  const ai = b & 0x1f;
  if (ai <= 23) return ai;
  if (ai === 24) return _rb();
  if (ai === 25) return _r16();
  if (ai === 26) return _r32();
  if (ai === 27) return Number(_r64());
  throw new Error("unsupported additional info " + ai);
}

function _dUvar(): bigint {
  const b = _rb();
  const ai = b & 0x1f;
  if (ai <= 23) return BigInt(ai);
  if (ai === 24) return BigInt(_rb());
  if (ai === 25) return BigInt(_r16());
  if (ai === 26) return BigInt(_r32());
  if (ai === 27) return _r64();
  throw new Error("expected uvarint");
}

function _dIvar(): bigint {
  const b = _rb();
  const maj = b >> 5;
  const ai = b & 0x1f;
  let v: bigint;
  if (ai <= 23) v = BigInt(ai);
  else if (ai === 24) v = BigInt(_rb());
  else if (ai === 25) v = BigInt(_r16());
  else if (ai === 26) v = BigInt(_r32());
  else if (ai === 27) v = _r64();
  else throw new Error("expected ivarint");
  if (maj === 0) return v;
  if (maj === 1) return -1n - v;
  throw new Error("expected ivarint");
}

function _dF16(): number { if (_rb() !== 0xf9) throw new Error("expected f16"); const v = _dv.getFloat16(_dp); _dp += 2; return v; }
function _dF32(): number { if (_rb() !== 0xfa) throw new Error("expected f32"); const v = _dv.getFloat32(_dp); _dp += 4; return v; }
function _dF64(): number { if (_rb() !== 0xfb) throw new Error("expected f64"); const v = _dv.getFloat64(_dp); _dp += 8; return v; }

function _dStr(): string {
  const len = _dMajLen(3);
  const s = _td.decode(_db.subarray(_dp, _dp + len));
  _dp += len;
  return s;
}

function _dBytes(): Uint8Array {
  const len = _dMajLen(2);
  const b = _db.slice(_dp, _dp + len);
  _dp += len;
  return b;
}

function _dArrHdr(): number { return _dMajLen(4); }

function _dSkip(): void {
  const b = _rb();
  const maj = b >> 5;
  const ai = b & 0x1f;
  if (maj === 7) {
    // simple/float
    if (ai <= 23) return;
    if (ai === 24) { _dp += 1; return; }
    if (ai === 25) { _dp += 2; return; }
    if (ai === 26) { _dp += 4; return; }
    if (ai === 27) { _dp += 8; return; }
    return;
  }
  let len: number;
  if (ai <= 23) len = ai;
  else if (ai === 24) len = _rb();
  else if (ai === 25) len = _r16();
  else if (ai === 26) len = _r32();
  else if (ai === 27) len = Number(_r64());
  else if (ai === 31) {
    // indefinite length
    while (_db[_dp] !== 0xff) _dSkip();
    _dp++; // consume break
    return;
  }
  else throw new Error("unsupported AI in skip");
  if (maj === 0 || maj === 1) return; // integer, value already consumed
  if (maj === 2 || maj === 3) { _dp += len; return; } // bytes/string
  if (maj === 4) { for (let i = 0; i < len; i++) _dSkip(); return; } // array
  if (maj === 5) { for (let i = 0; i < len * 2; i++) _dSkip(); return; } // map
  if (maj === 6) { _dSkip(); return; } // tag: skip the wrapped item
}
