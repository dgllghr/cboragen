use minicbor::{Encode, Decode};

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct Primitives {
    #[n(0)] pub b: bool,
    #[n(1)] pub u8v: u8,
    #[n(2)] pub u16v: u16,
    #[n(3)] pub u32v: u32,
    #[n(4)] pub u64v: u64,
    #[n(5)] pub i8v: i8,
    #[n(6)] pub i16v: i16,
    #[n(7)] pub i32v: i32,
    #[n(8)] pub i64v: i64,
    #[n(9)] pub f32v: f32,
    #[n(10)] pub f64v: f64,
    #[n(11)] pub uvar: u64,
    #[n(12)] pub ivar: i64,
    #[n(13)] pub str_: String,
    #[cbor(n(14), with = "minicbor::bytes")]
    pub bin: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct WithOptionals {
    #[n(0)] pub required: String,
    #[n(1)] pub maybe: Option<u32>,
    #[n(2)] pub maybe_str: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Encode, Decode)]
#[cbor(index_only)]
pub enum Color {
    #[n(0)] Red,
    #[n(1)] Green,
    #[n(2)] Blue,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct ShapeRect {
    #[n(0)] pub w: f64,
    #[n(1)] pub h: f64,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub enum Shape {
    #[n(0)] Circle(#[n(0)] f64),
    #[n(1)] Rect(#[n(0)] ShapeRect),
    #[n(2)] Point,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct Numbers {
    #[n(0)] pub values: Vec<i32>,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct Vec3 {
    #[n(0)] pub xyz: Vec<f64>,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct ColoredShape {
    #[n(0)] pub color: Color,
    #[n(1)] pub shape: Shape,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct Entity {
    #[n(0)] pub id: u64,
    #[n(1)] pub name: String,
}

#[derive(Debug, Clone, PartialEq, Encode, Decode)]
pub struct Matrix {
    #[n(0)] pub rows: Vec<Vec<f64>>,
}
