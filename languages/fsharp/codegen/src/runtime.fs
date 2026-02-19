module internal Cbor =

    open System

    // === Writer ===

    type Writer() =
        let mutable buf: byte array = Array.zeroCreate 256
        let mutable pos: int = 0

        member private _.Grow(n: int) =
            if pos + n > buf.Length then
                let mutable cap = buf.Length
                while cap < pos + n do
                    cap <- cap * 2
                let nb = Array.zeroCreate<byte> cap
                Buffer.BlockCopy(buf, 0, nb, 0, pos)
                buf <- nb

        member _.Reset() = pos <- 0

        member _.Finish() : byte array =
            let r = Array.zeroCreate<byte> pos
            Buffer.BlockCopy(buf, 0, r, 0, pos)
            pos <- 0
            r

        member this.WriteByte(b: byte) =
            this.Grow(1)
            buf.[pos] <- b
            pos <- pos + 1

        member private this.W16(v: uint16) =
            this.Grow(2)
            buf.[pos] <- byte (v >>> 8)
            buf.[pos + 1] <- byte v
            pos <- pos + 2

        member private this.W32(v: uint32) =
            this.Grow(4)
            buf.[pos] <- byte (v >>> 24)
            buf.[pos + 1] <- byte (v >>> 16)
            buf.[pos + 2] <- byte (v >>> 8)
            buf.[pos + 3] <- byte v
            pos <- pos + 4

        member private this.W64(v: uint64) =
            this.Grow(8)
            buf.[pos] <- byte (v >>> 56)
            buf.[pos + 1] <- byte (v >>> 48)
            buf.[pos + 2] <- byte (v >>> 40)
            buf.[pos + 3] <- byte (v >>> 32)
            buf.[pos + 4] <- byte (v >>> 24)
            buf.[pos + 5] <- byte (v >>> 16)
            buf.[pos + 6] <- byte (v >>> 8)
            buf.[pos + 7] <- byte v
            pos <- pos + 8

        member this.WriteMajLen(baseVal: byte, n: uint64) =
            if n <= 23UL then
                this.WriteByte(baseVal ||| byte n)
            elif n <= 0xFFUL then
                this.WriteByte(baseVal ||| 24uy)
                this.WriteByte(byte n)
            elif n <= 0xFFFFUL then
                this.WriteByte(baseVal ||| 25uy)
                this.W16(uint16 n)
            elif n <= 0xFFFFFFFFUL then
                this.WriteByte(baseVal ||| 26uy)
                this.W32(uint32 n)
            else
                this.WriteByte(baseVal ||| 27uy)
                this.W64(n)

        member this.WriteBool(v: bool) =
            this.WriteByte(if v then 0xF5uy else 0xF4uy)

        member this.WriteNull() =
            this.WriteByte(0xF6uy)

        member this.WriteU8(v: byte) =
            this.WriteByte(0x18uy)
            this.WriteByte(v)

        member this.WriteU16(v: uint16) =
            this.WriteByte(0x19uy)
            this.W16(v)

        member this.WriteU32(v: uint32) =
            this.WriteByte(0x1Auy)
            this.W32(v)

        member this.WriteU64(v: uint64) =
            this.WriteByte(0x1Buy)
            this.W64(v)

        member this.WriteI8(v: sbyte) =
            if v >= 0y then
                this.WriteByte(0x18uy)
                this.WriteByte(byte v)
            else
                this.WriteByte(0x38uy)
                this.WriteByte(byte (-1y - v))

        member this.WriteI16(v: int16) =
            if v >= 0s then
                this.WriteByte(0x19uy)
                this.W16(uint16 v)
            else
                this.WriteByte(0x39uy)
                this.W16(uint16 (-1s - v))

        member this.WriteI32(v: int) =
            if v >= 0 then
                this.WriteByte(0x1Auy)
                this.W32(uint32 v)
            else
                this.WriteByte(0x3Auy)
                this.W32(uint32 (-1 - v))

        member this.WriteI64(v: int64) =
            if v >= 0L then
                this.WriteByte(0x1Buy)
                this.W64(uint64 v)
            else
                this.WriteByte(0x3Buy)
                this.W64(uint64 (-1L - v))

        member this.WriteUvarint(v: uint64) =
            this.WriteMajLen(0x00uy, v)

        member this.WriteIvarint(v: int64) =
            if v >= 0L then
                this.WriteMajLen(0x00uy, uint64 v)
            else
                this.WriteMajLen(0x20uy, uint64 (-1L - v))

        member this.WriteF16(v: Half) =
            this.WriteByte(0xF9uy)
            let bytes = BitConverter.GetBytes(v)
            if not BitConverter.IsLittleEndian then
                this.Grow(2)
                buf.[pos] <- bytes.[0]
                buf.[pos + 1] <- bytes.[1]
                pos <- pos + 2
            else
                this.Grow(2)
                buf.[pos] <- bytes.[1]
                buf.[pos + 1] <- bytes.[0]
                pos <- pos + 2

        member this.WriteF32(v: float32) =
            this.WriteByte(0xFAuy)
            let bits = BitConverter.SingleToUInt32Bits(v)
            this.W32(bits)

        member this.WriteF64(v: float) =
            this.WriteByte(0xFBuy)
            let bits = BitConverter.DoubleToUInt64Bits(v)
            this.W64(bits)

        member this.WriteString(v: string) =
            let enc = Text.Encoding.UTF8.GetBytes(v)
            this.WriteMajLen(0x60uy, uint64 enc.Length)
            this.Grow(enc.Length)
            Buffer.BlockCopy(enc, 0, buf, pos, enc.Length)
            pos <- pos + enc.Length

        member this.WriteBytes(v: byte array) =
            this.WriteMajLen(0x40uy, uint64 v.Length)
            this.Grow(v.Length)
            Buffer.BlockCopy(v, 0, buf, pos, v.Length)
            pos <- pos + v.Length

        member this.WriteArrayHeader(len: int) =
            this.WriteMajLen(0x80uy, uint64 len)

        member this.WriteTagHeader(tag: uint32) =
            this.WriteMajLen(0xC0uy, uint64 tag)

    // === Reader ===

    type Reader(data: byte array) =
        let mutable p: int = 0

        member _.PeekByte() : byte = data.[p]

        member _.ReadByte() : byte =
            let b = data.[p]
            p <- p + 1
            b

        member private _.R16() : uint16 =
            let v = (uint16 data.[p] <<< 8) ||| uint16 data.[p + 1]
            p <- p + 2
            v

        member private _.R32() : uint32 =
            let v =
                (uint32 data.[p] <<< 24)
                ||| (uint32 data.[p + 1] <<< 16)
                ||| (uint32 data.[p + 2] <<< 8)
                ||| uint32 data.[p + 3]
            p <- p + 4
            v

        member private _.R64() : uint64 =
            let v =
                (uint64 data.[p] <<< 56)
                ||| (uint64 data.[p + 1] <<< 48)
                ||| (uint64 data.[p + 2] <<< 40)
                ||| (uint64 data.[p + 3] <<< 32)
                ||| (uint64 data.[p + 4] <<< 24)
                ||| (uint64 data.[p + 5] <<< 16)
                ||| (uint64 data.[p + 6] <<< 8)
                ||| uint64 data.[p + 7]
            p <- p + 8
            v

        member this.ReadBool() : bool =
            let b = this.ReadByte()
            if b = 0xF5uy then true
            elif b = 0xF4uy then false
            else failwith "expected bool"

        member this.ReadU8() : byte =
            if this.ReadByte() <> 0x18uy then failwith "expected u8"
            this.ReadByte()

        member this.ReadU16() : uint16 =
            if this.ReadByte() <> 0x19uy then failwith "expected u16"
            this.R16()

        member this.ReadU32() : uint32 =
            if this.ReadByte() <> 0x1Auy then failwith "expected u32"
            this.R32()

        member this.ReadU64() : uint64 =
            if this.ReadByte() <> 0x1Buy then failwith "expected u64"
            this.R64()

        member this.ReadI8() : sbyte =
            let b = this.ReadByte()
            if b = 0x18uy then sbyte (this.ReadByte())
            elif b = 0x38uy then -1y - sbyte (this.ReadByte())
            else failwith "expected i8"

        member this.ReadI16() : int16 =
            let b = this.ReadByte()
            if b = 0x19uy then int16 (this.R16())
            elif b = 0x39uy then -1s - int16 (this.R16())
            else failwith "expected i16"

        member this.ReadI32() : int =
            let b = this.ReadByte()
            if b = 0x1Auy then int (this.R32())
            elif b = 0x3Auy then -1 - int (this.R32())
            else failwith "expected i32"

        member this.ReadI64() : int64 =
            let b = this.ReadByte()
            if b = 0x1Buy then int64 (this.R64())
            elif b = 0x3Buy then -1L - int64 (this.R64())
            else failwith "expected i64"

        member this.ReadMajLen(expectedMajor: int) : int =
            let b = this.ReadByte()
            let maj = int b >>> 5
            if maj <> expectedMajor then
                failwithf "unexpected major type %d" maj
            let ai = int b &&& 0x1F
            if ai <= 23 then ai
            elif ai = 24 then int (this.ReadByte())
            elif ai = 25 then int (this.R16())
            elif ai = 26 then int (this.R32())
            elif ai = 27 then int (this.R64())
            else failwithf "unsupported additional info %d" ai

        member this.ReadUvarint() : uint64 =
            let b = this.ReadByte()
            let ai = int b &&& 0x1F
            if ai <= 23 then uint64 ai
            elif ai = 24 then uint64 (this.ReadByte())
            elif ai = 25 then uint64 (this.R16())
            elif ai = 26 then uint64 (this.R32())
            elif ai = 27 then this.R64()
            else failwith "expected uvarint"

        member this.ReadIvarint() : int64 =
            let b = this.ReadByte()
            let maj = int b >>> 5
            let ai = int b &&& 0x1F
            let v =
                if ai <= 23 then int64 ai
                elif ai = 24 then int64 (this.ReadByte())
                elif ai = 25 then int64 (this.R16())
                elif ai = 26 then int64 (this.R32())
                elif ai = 27 then int64 (this.R64())
                else failwith "expected ivarint"
            if maj = 0 then v
            elif maj = 1 then -1L - v
            else failwith "expected ivarint"

        member this.ReadF16() : Half =
            if this.ReadByte() <> 0xF9uy then failwith "expected f16"
            let bytes =
                if BitConverter.IsLittleEndian then
                    [| data.[p + 1]; data.[p] |]
                else
                    [| data.[p]; data.[p + 1] |]
            p <- p + 2
            BitConverter.ToHalf(bytes, 0)

        member this.ReadF32() : float32 =
            if this.ReadByte() <> 0xFAuy then failwith "expected f32"
            let bits = this.R32()
            BitConverter.UInt32BitsToSingle(bits)

        member this.ReadF64() : float =
            if this.ReadByte() <> 0xFBuy then failwith "expected f64"
            let bits = this.R64()
            BitConverter.UInt64BitsToDouble(bits)

        member this.ReadString() : string =
            let len = this.ReadMajLen(3)
            let s = Text.Encoding.UTF8.GetString(data, p, len)
            p <- p + len
            s

        member this.ReadBytes() : byte array =
            let len = this.ReadMajLen(2)
            let b = Array.zeroCreate<byte> len
            Buffer.BlockCopy(data, p, b, 0, len)
            p <- p + len
            b

        member this.ReadArrayHeader() : int =
            this.ReadMajLen(4)

        member this.ReadTagHeader() : uint32 =
            uint32 (this.ReadMajLen(6))

        member this.Skip() : unit =
            let b = this.ReadByte()
            let maj = int b >>> 5
            let ai = int b &&& 0x1F
            if maj = 7 then
                if ai <= 23 then ()
                elif ai = 24 then p <- p + 1
                elif ai = 25 then p <- p + 2
                elif ai = 26 then p <- p + 4
                elif ai = 27 then p <- p + 8
            else
                let len =
                    if ai <= 23 then ai
                    elif ai = 24 then int (this.ReadByte())
                    elif ai = 25 then int (this.R16())
                    elif ai = 26 then int (this.R32())
                    elif ai = 27 then int (this.R64())
                    elif ai = 31 then
                        while data.[p] <> 0xFFuy do
                            this.Skip()
                        p <- p + 1
                        -1
                    else
                        failwithf "unsupported AI in skip %d" ai
                if len >= 0 then
                    if maj = 0 || maj = 1 then ()
                    elif maj = 2 || maj = 3 then p <- p + len
                    elif maj = 4 then
                        for _ = 0 to len - 1 do
                            this.Skip()
                    elif maj = 5 then
                        for _ = 0 to len * 2 - 1 do
                            this.Skip()
                    elif maj = 6 then this.Skip()
