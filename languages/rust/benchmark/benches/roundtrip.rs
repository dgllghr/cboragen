use criterion::{black_box, criterion_group, criterion_main, Criterion};

use cboragen_bench::generated as cbg;
use cboragen_bench::minicbor_types as mini;

// --- Test data constructors ---

fn cbg_primitives() -> cbg::Primitives {
    cbg::Primitives {
        b: true,
        u8v: 255,
        u16v: 1000,
        u32v: 100_000,
        u64v: 10_000_000_000,
        i8v: -128,
        i16v: -1000,
        i32v: -100_000,
        i64v: -10_000_000_000,
        f32v: 3.14,
        f64v: 2.718281828,
        uvar: 42,
        ivar: -42,
        str_: "hello world".to_string(),
        bin: vec![1, 2, 3, 4, 5, 6, 7, 8],
    }
}

fn mini_primitives() -> mini::Primitives {
    mini::Primitives {
        b: true,
        u8v: 255,
        u16v: 1000,
        u32v: 100_000,
        u64v: 10_000_000_000,
        i8v: -128,
        i16v: -1000,
        i32v: -100_000,
        i64v: -10_000_000_000,
        f32v: 3.14,
        f64v: 2.718281828,
        uvar: 42,
        ivar: -42,
        str_: "hello world".to_string(),
        bin: vec![1, 2, 3, 4, 5, 6, 7, 8],
    }
}

fn cbg_entity() -> cbg::Entity {
    cbg::Entity { id: 42, name: "Alice".to_string() }
}

fn mini_entity() -> mini::Entity {
    mini::Entity { id: 42, name: "Alice".to_string() }
}

fn cbg_numbers() -> cbg::Numbers {
    cbg::Numbers { values: (0..100).collect() }
}

fn mini_numbers() -> mini::Numbers {
    mini::Numbers { values: (0..100).collect() }
}

fn cbg_colored_shape() -> cbg::ColoredShape {
    cbg::ColoredShape {
        color: cbg::Color::Blue,
        shape: cbg::Shape::Rect(cbg::ShapeRect { w: 10.0, h: 20.0 }),
    }
}

fn mini_colored_shape() -> mini::ColoredShape {
    mini::ColoredShape {
        color: mini::Color::Blue,
        shape: mini::Shape::Rect(mini::ShapeRect { w: 10.0, h: 20.0 }),
    }
}

fn cbg_matrix() -> cbg::Matrix {
    cbg::Matrix {
        rows: (0..10).map(|i| (0..10).map(|j| (i * 10 + j) as f64).collect()).collect(),
    }
}

fn mini_matrix() -> mini::Matrix {
    mini::Matrix {
        rows: (0..10).map(|i| (0..10).map(|j| (i * 10 + j) as f64).collect()).collect(),
    }
}

// --- Benchmarks ---

fn bench_primitives(c: &mut Criterion) {
    let mut g = c.benchmark_group("primitives");

    let cbg_val = cbg_primitives();
    let cbg_encoded = cbg_val.encode();
    g.bench_function("cboragen/encode", |b| {
        b.iter(|| black_box(&cbg_val).encode())
    });
    g.bench_function("cboragen/decode", |b| {
        b.iter(|| cbg::Primitives::decode(black_box(&cbg_encoded)))
    });

    let mini_val = mini_primitives();
    let mini_encoded = minicbor::to_vec(&mini_val).expect("minicbor encode");
    g.bench_function("minicbor/encode", |b| {
        b.iter(|| minicbor::to_vec(black_box(&mini_val)))
    });
    g.bench_function("minicbor/decode", |b| {
        b.iter(|| minicbor::decode::<mini::Primitives>(black_box(&mini_encoded)))
    });

    g.finish();
}

fn bench_entity(c: &mut Criterion) {
    let mut g = c.benchmark_group("entity");

    let cbg_val = cbg_entity();
    let cbg_encoded = cbg_val.encode();
    g.bench_function("cboragen/encode", |b| {
        b.iter(|| black_box(&cbg_val).encode())
    });
    g.bench_function("cboragen/decode", |b| {
        b.iter(|| cbg::Entity::decode(black_box(&cbg_encoded)))
    });

    let mini_val = mini_entity();
    let mini_encoded = minicbor::to_vec(&mini_val).expect("minicbor encode");
    g.bench_function("minicbor/encode", |b| {
        b.iter(|| minicbor::to_vec(black_box(&mini_val)))
    });
    g.bench_function("minicbor/decode", |b| {
        b.iter(|| minicbor::decode::<mini::Entity>(black_box(&mini_encoded)))
    });

    g.finish();
}

fn bench_numbers(c: &mut Criterion) {
    let mut g = c.benchmark_group("numbers_100");

    let cbg_val = cbg_numbers();
    let cbg_encoded = cbg_val.encode();
    g.bench_function("cboragen/encode", |b| {
        b.iter(|| black_box(&cbg_val).encode())
    });
    g.bench_function("cboragen/decode", |b| {
        b.iter(|| cbg::Numbers::decode(black_box(&cbg_encoded)))
    });

    let mini_val = mini_numbers();
    let mini_encoded = minicbor::to_vec(&mini_val).expect("minicbor encode");
    g.bench_function("minicbor/encode", |b| {
        b.iter(|| minicbor::to_vec(black_box(&mini_val)))
    });
    g.bench_function("minicbor/decode", |b| {
        b.iter(|| minicbor::decode::<mini::Numbers>(black_box(&mini_encoded)))
    });

    g.finish();
}

fn bench_colored_shape(c: &mut Criterion) {
    let mut g = c.benchmark_group("colored_shape");

    let cbg_val = cbg_colored_shape();
    let cbg_encoded = cbg_val.encode();
    g.bench_function("cboragen/encode", |b| {
        b.iter(|| black_box(&cbg_val).encode())
    });
    g.bench_function("cboragen/decode", |b| {
        b.iter(|| cbg::ColoredShape::decode(black_box(&cbg_encoded)))
    });

    let mini_val = mini_colored_shape();
    let mini_encoded = minicbor::to_vec(&mini_val).expect("minicbor encode");
    g.bench_function("minicbor/encode", |b| {
        b.iter(|| minicbor::to_vec(black_box(&mini_val)))
    });
    g.bench_function("minicbor/decode", |b| {
        b.iter(|| minicbor::decode::<mini::ColoredShape>(black_box(&mini_encoded)))
    });

    g.finish();
}

fn bench_matrix(c: &mut Criterion) {
    let mut g = c.benchmark_group("matrix_10x10");

    let cbg_val = cbg_matrix();
    let cbg_encoded = cbg_val.encode();
    g.bench_function("cboragen/encode", |b| {
        b.iter(|| black_box(&cbg_val).encode())
    });
    g.bench_function("cboragen/decode", |b| {
        b.iter(|| cbg::Matrix::decode(black_box(&cbg_encoded)))
    });

    let mini_val = mini_matrix();
    let mini_encoded = minicbor::to_vec(&mini_val).expect("minicbor encode");
    g.bench_function("minicbor/encode", |b| {
        b.iter(|| minicbor::to_vec(black_box(&mini_val)))
    });
    g.bench_function("minicbor/decode", |b| {
        b.iter(|| minicbor::decode::<mini::Matrix>(black_box(&mini_encoded)))
    });

    g.finish();
}

criterion_group!(
    benches,
    bench_primitives,
    bench_entity,
    bench_numbers,
    bench_colored_shape,
    bench_matrix,
);
criterion_main!(benches);
