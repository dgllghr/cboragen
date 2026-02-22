/// CBOR Writer — growable byte buffer for encoding.
pub struct Writer {
    buf: Vec<u8>,
}

impl Writer {
    pub fn new() -> Self {
        Writer { buf: Vec::with_capacity(256) }
    }

    pub fn finish(self) -> Vec<u8> {
        self.buf
    }

    pub fn write_bool(&mut self, v: bool) {
        self.buf.push(if v { 0xf5 } else { 0xf4 });
    }

    pub fn write_null(&mut self) {
        self.buf.push(0xf6);
    }

    // Fixed-width unsigned integers — always full-width encoding
    pub fn write_u8(&mut self, v: u8) {
        self.buf.push(0x18);
        self.buf.push(v);
    }

    pub fn write_u16(&mut self, v: u16) {
        self.buf.push(0x19);
        self.buf.extend_from_slice(&v.to_be_bytes());
    }

    pub fn write_u32(&mut self, v: u32) {
        self.buf.push(0x1a);
        self.buf.extend_from_slice(&v.to_be_bytes());
    }

    pub fn write_u64(&mut self, v: u64) {
        self.buf.push(0x1b);
        self.buf.extend_from_slice(&v.to_be_bytes());
    }

    // Fixed-width signed integers
    pub fn write_i8(&mut self, v: i8) {
        if v >= 0 {
            self.buf.push(0x18);
            self.buf.push(v as u8);
        } else {
            self.buf.push(0x38);
            self.buf.push((-1 - v) as u8);
        }
    }

    pub fn write_i16(&mut self, v: i16) {
        if v >= 0 {
            self.buf.push(0x19);
            self.buf.extend_from_slice(&(v as u16).to_be_bytes());
        } else {
            self.buf.push(0x39);
            self.buf.extend_from_slice(&((-1 - v) as u16).to_be_bytes());
        }
    }

    pub fn write_i32(&mut self, v: i32) {
        if v >= 0 {
            self.buf.push(0x1a);
            self.buf.extend_from_slice(&(v as u32).to_be_bytes());
        } else {
            self.buf.push(0x3a);
            self.buf.extend_from_slice(&((-1 - v) as u32).to_be_bytes());
        }
    }

    pub fn write_i64(&mut self, v: i64) {
        if v >= 0 {
            self.buf.push(0x1b);
            self.buf.extend_from_slice(&(v as u64).to_be_bytes());
        } else {
            self.buf.push(0x3b);
            self.buf.extend_from_slice(&((-1i64 - v) as u64).to_be_bytes());
        }
    }

    // Varints — minimal CBOR encoding
    pub fn write_uvarint(&mut self, v: u64) {
        self.write_maj_len(0x00, v);
    }

    pub fn write_ivarint(&mut self, v: i64) {
        if v >= 0 {
            self.write_maj_len(0x00, v as u64);
        } else {
            self.write_maj_len(0x20, (-1 - v) as u64);
        }
    }

    // Floats
    pub fn write_f16(&mut self, v: f32) {
        self.buf.push(0xf9);
        self.buf.extend_from_slice(&f32_to_f16_bits(v).to_be_bytes());
    }

    pub fn write_f32(&mut self, v: f32) {
        self.buf.push(0xfa);
        self.buf.extend_from_slice(&v.to_bits().to_be_bytes());
    }

    pub fn write_f64(&mut self, v: f64) {
        self.buf.push(0xfb);
        self.buf.extend_from_slice(&v.to_bits().to_be_bytes());
    }

    // String and bytes
    pub fn write_string(&mut self, v: &str) {
        self.write_maj_len(0x60, v.len() as u64);
        self.buf.extend_from_slice(v.as_bytes());
    }

    pub fn write_bytes(&mut self, v: &[u8]) {
        self.write_maj_len(0x40, v.len() as u64);
        self.buf.extend_from_slice(v);
    }

    // Structural
    pub fn write_array_header(&mut self, len: usize) {
        self.write_maj_len(0x80, len as u64);
    }

    pub fn write_tag_header(&mut self, tag: u64) {
        self.write_maj_len(0xc0, tag);
    }

    pub fn write_byte(&mut self, b: u8) {
        self.buf.push(b);
    }

    fn write_maj_len(&mut self, base: u8, n: u64) {
        if n <= 23 {
            self.buf.push(base | n as u8);
        } else if n <= 0xff {
            self.buf.push(base | 24);
            self.buf.push(n as u8);
        } else if n <= 0xffff {
            self.buf.push(base | 25);
            self.buf.extend_from_slice(&(n as u16).to_be_bytes());
        } else if n <= 0xffff_ffff {
            self.buf.push(base | 26);
            self.buf.extend_from_slice(&(n as u32).to_be_bytes());
        } else {
            self.buf.push(base | 27);
            self.buf.extend_from_slice(&n.to_be_bytes());
        }
    }
}

impl Default for Writer {
    fn default() -> Self {
        Self::new()
    }
}

/// Decode error returned by Reader methods.
#[derive(Debug)]
pub enum DecodeError {
    UnexpectedEnd,
    InvalidData(String),
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DecodeError::UnexpectedEnd => write!(f, "unexpected end of CBOR data"),
            DecodeError::InvalidData(msg) => write!(f, "invalid CBOR data: {msg}"),
        }
    }
}

impl std::error::Error for DecodeError {}

/// CBOR Reader — reads from a byte slice.
pub struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Reader { data, pos: 0 }
    }

    pub fn read_bool(&mut self) -> Result<bool, DecodeError> {
        let b = self.read_byte()?;
        match b {
            0xf5 => Ok(true),
            0xf4 => Ok(false),
            _ => Err(DecodeError::InvalidData(format!("expected bool, got 0x{b:02x}"))),
        }
    }

    // Fixed-width unsigned
    pub fn read_u8(&mut self) -> Result<u8, DecodeError> {
        let b = self.read_byte()?;
        if b != 0x18 {
            return Err(DecodeError::InvalidData(format!("expected u8 header 0x18, got 0x{b:02x}")));
        }
        self.read_byte()
    }

    pub fn read_u16(&mut self) -> Result<u16, DecodeError> {
        let b = self.read_byte()?;
        if b != 0x19 {
            return Err(DecodeError::InvalidData(format!("expected u16 header 0x19, got 0x{b:02x}")));
        }
        self.read_u16_raw()
    }

    pub fn read_u32(&mut self) -> Result<u32, DecodeError> {
        let b = self.read_byte()?;
        if b != 0x1a {
            return Err(DecodeError::InvalidData(format!("expected u32 header 0x1a, got 0x{b:02x}")));
        }
        self.read_u32_raw()
    }

    pub fn read_u64(&mut self) -> Result<u64, DecodeError> {
        let b = self.read_byte()?;
        if b != 0x1b {
            return Err(DecodeError::InvalidData(format!("expected u64 header 0x1b, got 0x{b:02x}")));
        }
        self.read_u64_raw()
    }

    // Fixed-width signed
    pub fn read_i8(&mut self) -> Result<i8, DecodeError> {
        let b = self.read_byte()?;
        match b {
            0x18 => Ok(self.read_byte()? as i8),
            0x38 => Ok(-1 - self.read_byte()? as i8),
            _ => Err(DecodeError::InvalidData(format!("expected i8, got 0x{b:02x}"))),
        }
    }

    pub fn read_i16(&mut self) -> Result<i16, DecodeError> {
        let b = self.read_byte()?;
        match b {
            0x19 => Ok(self.read_u16_raw()? as i16),
            0x39 => Ok(-1 - self.read_u16_raw()? as i16),
            _ => Err(DecodeError::InvalidData(format!("expected i16, got 0x{b:02x}"))),
        }
    }

    pub fn read_i32(&mut self) -> Result<i32, DecodeError> {
        let b = self.read_byte()?;
        match b {
            0x1a => Ok(self.read_u32_raw()? as i32),
            0x3a => Ok(-1 - self.read_u32_raw()? as i32),
            _ => Err(DecodeError::InvalidData(format!("expected i32, got 0x{b:02x}"))),
        }
    }

    pub fn read_i64(&mut self) -> Result<i64, DecodeError> {
        let b = self.read_byte()?;
        match b {
            0x1b => Ok(self.read_u64_raw()? as i64),
            0x3b => Ok(-1 - self.read_u64_raw()? as i64),
            _ => Err(DecodeError::InvalidData(format!("expected i64, got 0x{b:02x}"))),
        }
    }

    // Varints
    pub fn read_uvarint(&mut self) -> Result<u64, DecodeError> {
        let b = self.read_byte()?;
        let ai = b & 0x1f;
        match ai {
            0..=23 => Ok(ai as u64),
            24 => Ok(self.read_byte()? as u64),
            25 => Ok(self.read_u16_raw()? as u64),
            26 => Ok(self.read_u32_raw()? as u64),
            27 => self.read_u64_raw(),
            _ => Err(DecodeError::InvalidData("expected uvarint".into())),
        }
    }

    pub fn read_ivarint(&mut self) -> Result<i64, DecodeError> {
        let b = self.read_byte()?;
        let maj = b >> 5;
        let ai = b & 0x1f;
        let v: u64 = match ai {
            0..=23 => ai as u64,
            24 => self.read_byte()? as u64,
            25 => self.read_u16_raw()? as u64,
            26 => self.read_u32_raw()? as u64,
            27 => self.read_u64_raw()?,
            _ => return Err(DecodeError::InvalidData("expected ivarint".into())),
        };
        match maj {
            0 => Ok(v as i64),
            1 => Ok(-1 - v as i64),
            _ => Err(DecodeError::InvalidData(format!("expected ivarint, got major type {maj}"))),
        }
    }

    // Floats
    pub fn read_f16(&mut self) -> Result<f32, DecodeError> {
        let b = self.read_byte()?;
        if b != 0xf9 {
            return Err(DecodeError::InvalidData(format!("expected f16 header 0xf9, got 0x{b:02x}")));
        }
        let bits = self.read_u16_raw()?;
        Ok(f16_bits_to_f32(bits))
    }

    pub fn read_f32(&mut self) -> Result<f32, DecodeError> {
        let b = self.read_byte()?;
        if b != 0xfa {
            return Err(DecodeError::InvalidData(format!("expected f32 header 0xfa, got 0x{b:02x}")));
        }
        let bits = self.read_u32_raw()?;
        Ok(f32::from_bits(bits))
    }

    pub fn read_f64(&mut self) -> Result<f64, DecodeError> {
        let b = self.read_byte()?;
        if b != 0xfb {
            return Err(DecodeError::InvalidData(format!("expected f64 header 0xfb, got 0x{b:02x}")));
        }
        let bits = self.read_u64_raw()?;
        Ok(f64::from_bits(bits))
    }

    // String and bytes
    pub fn read_string(&mut self) -> Result<String, DecodeError> {
        let len = self.read_maj_len(3)?;
        if self.pos + len > self.data.len() {
            return Err(DecodeError::UnexpectedEnd);
        }
        let s = std::str::from_utf8(&self.data[self.pos..self.pos + len])
            .map_err(|e| DecodeError::InvalidData(format!("invalid UTF-8 in CBOR string: {e}")))?;
        self.pos += len;
        Ok(s.to_string())
    }

    pub fn read_bytes(&mut self) -> Result<Vec<u8>, DecodeError> {
        let len = self.read_maj_len(2)?;
        if self.pos + len > self.data.len() {
            return Err(DecodeError::UnexpectedEnd);
        }
        let b = self.data[self.pos..self.pos + len].to_vec();
        self.pos += len;
        Ok(b)
    }

    // Structural
    pub fn read_array_header(&mut self) -> Result<usize, DecodeError> {
        self.read_maj_len(4)
    }

    pub fn read_byte(&mut self) -> Result<u8, DecodeError> {
        let b = *self.data.get(self.pos).ok_or(DecodeError::UnexpectedEnd)?;
        self.pos += 1;
        Ok(b)
    }

    pub fn peek_byte(&self) -> Result<u8, DecodeError> {
        self.data.get(self.pos).copied().ok_or(DecodeError::UnexpectedEnd)
    }

    pub fn skip(&mut self) -> Result<(), DecodeError> {
        let b = self.read_byte()?;
        let maj = b >> 5;
        let ai = b & 0x1f;

        if maj == 7 {
            // simple/float
            let skip_len = match ai {
                0..=23 => 0,
                24 => 1,
                25 => 2,
                26 => 4,
                27 => 8,
                _ => 0,
            };
            if self.pos + skip_len > self.data.len() {
                return Err(DecodeError::UnexpectedEnd);
            }
            self.pos += skip_len;
            return Ok(());
        }

        let len: usize = if ai <= 23 {
            ai as usize
        } else if ai == 24 {
            self.read_byte()? as usize
        } else if ai == 25 {
            self.read_u16_raw()? as usize
        } else if ai == 26 {
            self.read_u32_raw()? as usize
        } else if ai == 27 {
            self.read_u64_raw()? as usize
        } else if ai == 31 {
            // indefinite length
            loop {
                let pb = *self.data.get(self.pos).ok_or(DecodeError::UnexpectedEnd)?;
                if pb == 0xff {
                    break;
                }
                self.skip()?;
            }
            self.pos += 1; // consume break
            return Ok(());
        } else {
            return Err(DecodeError::InvalidData(format!("unsupported additional info {ai} in skip")));
        };

        match maj {
            0 | 1 => {} // integer, value already consumed
            2 | 3 => {
                if self.pos + len > self.data.len() {
                    return Err(DecodeError::UnexpectedEnd);
                }
                self.pos += len;
            }
            4 => { for _ in 0..len { self.skip()?; } }
            5 => { for _ in 0..len * 2 { self.skip()?; } }
            6 => { self.skip()?; }
            _ => return Err(DecodeError::InvalidData(format!("unexpected major type {maj} in skip"))),
        }
        Ok(())
    }

    fn read_u16_raw(&mut self) -> Result<u16, DecodeError> {
        if self.pos + 2 > self.data.len() {
            return Err(DecodeError::UnexpectedEnd);
        }
        let v = u16::from_be_bytes([self.data[self.pos], self.data[self.pos + 1]]);
        self.pos += 2;
        Ok(v)
    }

    fn read_u32_raw(&mut self) -> Result<u32, DecodeError> {
        if self.pos + 4 > self.data.len() {
            return Err(DecodeError::UnexpectedEnd);
        }
        let v = u32::from_be_bytes([
            self.data[self.pos], self.data[self.pos + 1],
            self.data[self.pos + 2], self.data[self.pos + 3],
        ]);
        self.pos += 4;
        Ok(v)
    }

    fn read_u64_raw(&mut self) -> Result<u64, DecodeError> {
        if self.pos + 8 > self.data.len() {
            return Err(DecodeError::UnexpectedEnd);
        }
        let v = u64::from_be_bytes([
            self.data[self.pos], self.data[self.pos + 1],
            self.data[self.pos + 2], self.data[self.pos + 3],
            self.data[self.pos + 4], self.data[self.pos + 5],
            self.data[self.pos + 6], self.data[self.pos + 7],
        ]);
        self.pos += 8;
        Ok(v)
    }

    fn read_maj_len(&mut self, expected_major: u8) -> Result<usize, DecodeError> {
        let b = self.read_byte()?;
        let maj = b >> 5;
        if maj != expected_major {
            return Err(DecodeError::InvalidData(format!("unexpected major type {maj}, expected {expected_major}")));
        }
        let ai = b & 0x1f;
        match ai {
            0..=23 => Ok(ai as usize),
            24 => Ok(self.read_byte()? as usize),
            25 => Ok(self.read_u16_raw()? as usize),
            26 => Ok(self.read_u32_raw()? as usize),
            27 => Ok(self.read_u64_raw()? as usize),
            _ => Err(DecodeError::InvalidData(format!("unsupported additional info {ai}"))),
        }
    }
}

// === IEEE 754 half-precision (f16) conversion ===

fn f32_to_f16_bits(v: f32) -> u16 {
    let bits = v.to_bits();
    let sign = ((bits >> 16) & 0x8000) as u16;
    let exp = ((bits >> 23) & 0xff) as i32;
    let frac = bits & 0x007f_ffff;

    if exp == 255 {
        // Inf or NaN
        if frac == 0 {
            return sign | 0x7c00;
        } else {
            return sign | 0x7c00 | (frac >> 13) as u16 | 1;
        }
    }

    let unbiased = exp - 127;
    if unbiased > 15 {
        // Overflow → Inf
        return sign | 0x7c00;
    }
    if unbiased < -24 {
        // Underflow → zero
        return sign;
    }
    if unbiased < -14 {
        // Subnormal
        let shift = -1 - unbiased + 10;
        let frac_with_hidden = frac | 0x0080_0000;
        return sign | (frac_with_hidden >> shift) as u16;
    }

    let h_exp = ((unbiased + 15) as u16) << 10;
    let h_frac = (frac >> 13) as u16;
    sign | h_exp | h_frac
}

fn f16_bits_to_f32(bits: u16) -> f32 {
    let sign = ((bits & 0x8000) as u32) << 16;
    let exp = ((bits >> 10) & 0x1f) as u32;
    let frac = (bits & 0x03ff) as u32;

    if exp == 0 {
        if frac == 0 {
            // Zero
            return f32::from_bits(sign);
        }
        // Subnormal → normalize
        let mut e = exp;
        let mut f = frac;
        while f & 0x0400 == 0 {
            f <<= 1;
            e += 1;
        }
        f &= 0x03ff;
        let f32_exp = (127 - 15 - e + 1) << 23;
        return f32::from_bits(sign | f32_exp | (f << 13));
    }
    if exp == 31 {
        // Inf or NaN
        let f32_frac = frac << 13;
        return f32::from_bits(sign | 0x7f80_0000 | f32_frac);
    }

    let f32_exp = (exp + 127 - 15) << 23;
    let f32_frac = frac << 13;
    f32::from_bits(sign | f32_exp | f32_frac)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_bool() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_bool(true);
        w.write_bool(false);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert_eq!(r.read_bool()?, true);
        assert_eq!(r.read_bool()?, false);
        Ok(())
    }

    #[test]
    fn roundtrip_integers() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_u8(42);
        w.write_u16(1000);
        w.write_u32(100000);
        w.write_u64(10000000000);
        w.write_i8(-5);
        w.write_i16(-1000);
        w.write_i32(-100000);
        w.write_i64(-10000000000);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert_eq!(r.read_u8()?, 42);
        assert_eq!(r.read_u16()?, 1000);
        assert_eq!(r.read_u32()?, 100000);
        assert_eq!(r.read_u64()?, 10000000000);
        assert_eq!(r.read_i8()?, -5);
        assert_eq!(r.read_i16()?, -1000);
        assert_eq!(r.read_i32()?, -100000);
        assert_eq!(r.read_i64()?, -10000000000);
        Ok(())
    }

    #[test]
    fn roundtrip_varints() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_uvarint(0);
        w.write_uvarint(23);
        w.write_uvarint(24);
        w.write_uvarint(255);
        w.write_uvarint(256);
        w.write_uvarint(65535);
        w.write_uvarint(65536);
        w.write_ivarint(0);
        w.write_ivarint(-1);
        w.write_ivarint(-100);
        w.write_ivarint(1000);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert_eq!(r.read_uvarint()?, 0);
        assert_eq!(r.read_uvarint()?, 23);
        assert_eq!(r.read_uvarint()?, 24);
        assert_eq!(r.read_uvarint()?, 255);
        assert_eq!(r.read_uvarint()?, 256);
        assert_eq!(r.read_uvarint()?, 65535);
        assert_eq!(r.read_uvarint()?, 65536);
        assert_eq!(r.read_ivarint()?, 0);
        assert_eq!(r.read_ivarint()?, -1);
        assert_eq!(r.read_ivarint()?, -100);
        assert_eq!(r.read_ivarint()?, 1000);
        Ok(())
    }

    #[test]
    fn roundtrip_floats() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_f32(3.14);
        w.write_f64(2.718281828);
        w.write_f16(1.5);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert!((r.read_f32()? - 3.14).abs() < 0.001);
        assert!((r.read_f64()? - 2.718281828).abs() < 0.000001);
        assert!((r.read_f16()? - 1.5).abs() < 0.01);
        Ok(())
    }

    #[test]
    fn roundtrip_string_bytes() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_string("hello");
        w.write_bytes(&[1, 2, 3]);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert_eq!(r.read_string()?, "hello");
        assert_eq!(r.read_bytes()?, vec![1, 2, 3]);
        Ok(())
    }

    #[test]
    fn roundtrip_array() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_array_header(3);
        w.write_u8(1);
        w.write_u8(2);
        w.write_u8(3);
        let data = w.finish();
        let mut r = Reader::new(&data);
        assert_eq!(r.read_array_header()?, 3);
        assert_eq!(r.read_u8()?, 1);
        assert_eq!(r.read_u8()?, 2);
        assert_eq!(r.read_u8()?, 3);
        Ok(())
    }

    #[test]
    fn test_skip() -> Result<(), DecodeError> {
        let mut w = Writer::new();
        w.write_u32(42);
        w.write_string("skipped");
        w.write_bool(true);
        let data = w.finish();
        let mut r = Reader::new(&data);
        r.skip()?;
        r.skip()?;
        assert_eq!(r.read_bool()?, true);
        Ok(())
    }

    #[test]
    fn test_f16_roundtrip() {
        let values: &[f32] = &[0.0, 1.0, -1.0, 0.5, 65504.0, 0.000061035156];
        for &v in values {
            let bits = f32_to_f16_bits(v);
            let back = f16_bits_to_f32(bits);
            assert!((back - v).abs() < 0.001 || (v == 0.0 && back == 0.0),
                "f16 roundtrip failed for {}: got {}", v, back);
        }
    }

    #[test]
    fn decode_error_on_empty() {
        let mut r = Reader::new(&[]);
        assert!(r.read_bool().is_err());
        assert!(r.read_u8().is_err());
        assert!(r.read_byte().is_err());
    }

    #[test]
    fn decode_error_on_invalid() {
        let mut r = Reader::new(&[0xff]);
        let err = r.read_bool().unwrap_err();
        assert!(matches!(err, DecodeError::InvalidData(_)));
    }
}
