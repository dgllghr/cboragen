import {
  type User,
  type UserMetadata,
  type Preferences,
  Theme,
  type Message,
  type Attachment,
  Priority,
  type Point3D,
  type PointCloud,
  type Numbers,
  encodeUser,
  decodeUser,
  encodeMessage,
  decodeMessage,
  encodePoint3D,
  decodePoint3D,
  encodePointCloud,
  decodePointCloud,
  encodeNumbers,
  decodeNumbers,
} from "./schema.gen";

// ============================================================================
// Test Data Generators
// ============================================================================

function generateUser(id: number): User {
  return {
    id: BigInt(id),
    username: `user_${id}`,
    email: `user${id}@example.com`,
    age: 25 + (id % 50),
    active: id % 2 === 0,
    score: Math.random() * 1000,
    tags: ["tag1", "tag2", "tag3"].slice(0, (id % 3) + 1),
    metadata:
      id % 3 === 0
        ? null
        : {
            createdAt: BigInt(Date.now() - id * 86400000),
            lastLogin: BigInt(Date.now()),
            loginCount: id * 10,
            preferences: {
              theme: (id % 3) as Theme,
              notifications: id % 2 === 0,
              language: "en-US",
            },
          },
  };
}

function generateMessage(id: number): Message {
  const sender = generateUser(id);
  const recipientCount = (id % 5) + 1;
  const recipients: User[] = [];
  for (let i = 0; i < recipientCount; i++) {
    recipients.push(generateUser(id * 100 + i));
  }

  const attachmentCount = id % 3;
  const attachments: Attachment[] = [];
  for (let i = 0; i < attachmentCount; i++) {
    attachments.push({
      name: `file_${i}.pdf`,
      mimeType: "application/pdf",
      size: 1024 * (i + 1),
      data: new Uint8Array(100).fill(i),
    });
  }

  return {
    id: BigInt(id),
    sender,
    recipients,
    subject: `Message subject ${id}`,
    body: `This is the body of message ${id}. `.repeat(5),
    attachments,
    priority: (id % 4) as Priority,
    timestamp: BigInt(Date.now()),
  };
}

function generatePoint3D(): Point3D {
  return {
    x: Math.random() * 1000,
    y: Math.random() * 1000,
    z: Math.random() * 1000,
  };
}

function generatePointCloud(size: number): PointCloud {
  const points: Point3D[] = [];
  for (let i = 0; i < size; i++) {
    points.push(generatePoint3D());
  }
  return {
    points,
    name: `cloud_${size}`,
  };
}

function generateNumbers(size: number): Numbers {
  const values: number[] = [];
  for (let i = 0; i < size; i++) {
    values.push(Math.random() * 1000);
  }
  return {
    values,
    label: `numbers_${size}`,
  };
}

// ============================================================================
// JSON helpers for Uint8Array and BigInt
// ============================================================================

function jsonReplacer(_key: string, value: unknown): unknown {
  if (typeof value === "bigint") {
    return { __bigint: value.toString() };
  }
  if (value instanceof Uint8Array) {
    return { __uint8array: Array.from(value) };
  }
  return value;
}

function jsonReviver(_key: string, value: unknown): unknown {
  if (value && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    if ("__bigint" in obj) {
      return BigInt(obj.__bigint as string);
    }
    if ("__uint8array" in obj) {
      return new Uint8Array(obj.__uint8array as number[]);
    }
  }
  return value;
}

// ============================================================================
// Benchmark Utilities
// ============================================================================

interface BenchmarkResult {
  name: string;
  ops: number;
  avgMs: number;
}

function benchmark(
  name: string,
  fn: () => void,
  minTimeMs: number = 500
): BenchmarkResult {
  // Warmup - run for at least 50ms or 100 iterations
  const warmupEnd = performance.now() + 50;
  let warmupCount = 0;
  while (performance.now() < warmupEnd && warmupCount < 100) {
    fn();
    warmupCount++;
  }

  // Benchmark - run for at least minTimeMs
  let iterations = 0;
  const start = performance.now();
  const endTime = start + minTimeMs;

  // Run in batches to reduce timing overhead
  const batchSize = Math.max(1, Math.floor(warmupCount / 10)) || 10;

  while (performance.now() < endTime) {
    for (let i = 0; i < batchSize; i++) {
      fn();
    }
    iterations += batchSize;
  }

  const totalMs = performance.now() - start;
  const ops = iterations / (totalMs / 1000);

  return {
    name,
    ops: Math.round(ops),
    avgMs: totalMs / iterations,
  };
}

function formatNumber(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(2) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(2) + "K";
  return n.toFixed(0);
}

function formatBytes(bytes: number): string {
  if (bytes >= 1024) return (bytes / 1024).toFixed(2) + " KB";
  return bytes + " B";
}

// ============================================================================
// UI
// ============================================================================

const logEl = document.getElementById("log")!;
const resultsEl = document.getElementById("results")!;
const runBtn = document.getElementById("runBtn") as HTMLButtonElement;
const runQuickBtn = document.getElementById("runQuickBtn") as HTMLButtonElement;

function log(msg: string) {
  logEl.textContent = msg;
}

function appendLog(msg: string) {
  logEl.textContent += "\n" + msg;
  logEl.scrollTop = logEl.scrollHeight;
}

interface BenchmarkSectionResult {
  name: string;
  description: string;
  cborSize: number;
  jsonSize: number;
  encodeCbor: BenchmarkResult;
  encodeJson: BenchmarkResult;
  decodeCbor: BenchmarkResult;
  decodeJson: BenchmarkResult;
}

function renderResults(
  correctness: { name: string; pass: boolean }[],
  sections: BenchmarkSectionResult[]
) {
  let html = "";

  // Correctness tests
  html += `<div class="benchmark-section">
    <h3>Correctness Tests</h3>
    <div class="correctness">
      ${correctness
        .map(
          (t) =>
            `<div class="test-result ${t.pass ? "pass" : "fail"}">${t.name}: ${t.pass ? "PASS" : "FAIL"}</div>`
        )
        .join("")}
    </div>
  </div>`;

  // Benchmark sections
  for (const section of sections) {
    const encodeRatio = section.encodeCbor.ops / section.encodeJson.ops;
    const decodeRatio = section.decodeCbor.ops / section.decodeJson.ops;
    const sizeRatio = section.jsonSize / section.cborSize;

    const encodeComparison =
      encodeRatio > 1
        ? `${encodeRatio.toFixed(2)}x faster`
        : `${(1 / encodeRatio).toFixed(2)}x slower`;
    const decodeComparison =
      decodeRatio > 1
        ? `${decodeRatio.toFixed(2)}x faster`
        : `${(1 / decodeRatio).toFixed(2)}x slower`;

    html += `<div class="benchmark-section">
      <h3>${section.name}</h3>
      <p>${section.description}</p>

      <h4>Size Comparison</h4>
      <table>
        <tr class="size-row">
          <td>cboragen</td>
          <td>${formatBytes(section.cborSize)}</td>
          <td rowspan="2" style="color: #4ade80; font-weight: bold;">${sizeRatio.toFixed(2)}x smaller</td>
        </tr>
        <tr class="size-row">
          <td>JSON</td>
          <td>${formatBytes(section.jsonSize)}</td>
        </tr>
      </table>

      <h4>Encode Performance</h4>
      <table>
        <tr>
          <th>Method</th>
          <th>Ops/sec</th>
          <th>Avg Time</th>
        </tr>
        <tr>
          <td>cboragen</td>
          <td>${formatNumber(section.encodeCbor.ops)}</td>
          <td>${section.encodeCbor.avgMs.toFixed(4)} ms</td>
        </tr>
        <tr>
          <td>JSON</td>
          <td>${formatNumber(section.encodeJson.ops)}</td>
          <td>${section.encodeJson.avgMs.toFixed(4)} ms</td>
        </tr>
      </table>
      <div class="comparison ${encodeRatio > 1 ? "faster" : "slower"}">
        cboragen is ${encodeComparison} than JSON
      </div>

      <h4>Decode Performance</h4>
      <table>
        <tr>
          <th>Method</th>
          <th>Ops/sec</th>
          <th>Avg Time</th>
        </tr>
        <tr>
          <td>cboragen</td>
          <td>${formatNumber(section.decodeCbor.ops)}</td>
          <td>${section.decodeCbor.avgMs.toFixed(4)} ms</td>
        </tr>
        <tr>
          <td>JSON</td>
          <td>${formatNumber(section.decodeJson.ops)}</td>
          <td>${section.decodeJson.avgMs.toFixed(4)} ms</td>
        </tr>
      </table>
      <div class="comparison ${decodeRatio > 1 ? "faster" : "slower"}">
        cboragen is ${decodeComparison} than JSON
      </div>
    </div>`;
  }

  resultsEl.innerHTML = html;
}

// ============================================================================
// Benchmarks
// ============================================================================

async function runBenchmarks(quick: boolean) {
  const benchTimeMs = quick ? 200 : 500;
  const correctness: { name: string; pass: boolean }[] = [];
  const sections: BenchmarkSectionResult[] = [];

  // Yield to UI
  await new Promise((r) => setTimeout(r, 10));

  // Correctness tests
  log("Running correctness tests...");
  await new Promise((r) => setTimeout(r, 10));

  try {
    const point = { x: 1.5, y: 2.5, z: 3.5 };
    const encoded = encodePoint3D(point);
    const decoded = decodePoint3D(encoded);
    correctness.push({
      name: "Point3D",
      pass:
        point.x === decoded.x &&
        point.y === decoded.y &&
        point.z === decoded.z,
    });
  } catch (e) {
    correctness.push({ name: "Point3D", pass: false });
  }

  try {
    const user = generateUser(42);
    const encoded = encodeUser(user);
    const decoded = decodeUser(encoded);
    correctness.push({
      name: "User",
      pass:
        JSON.stringify(user, jsonReplacer) ===
        JSON.stringify(decoded, jsonReplacer),
    });
  } catch (e) {
    correctness.push({ name: "User", pass: false });
  }

  try {
    const message = generateMessage(1);
    const encoded = encodeMessage(message);
    const decoded = decodeMessage(encoded);
    correctness.push({
      name: "Message",
      pass:
        JSON.stringify(message, jsonReplacer) ===
        JSON.stringify(decoded, jsonReplacer),
    });
  } catch (e) {
    correctness.push({ name: "Message", pass: false });
  }

  try {
    const cloud = generatePointCloud(10);
    const encoded = encodePointCloud(cloud);
    const decoded = decodePointCloud(encoded);
    correctness.push({
      name: "PointCloud",
      pass: JSON.stringify(cloud) === JSON.stringify(decoded),
    });
  } catch (e) {
    correctness.push({ name: "PointCloud", pass: false });
  }

  try {
    const nums = generateNumbers(100);
    const encoded = encodeNumbers(nums);
    const decoded = decodeNumbers(encoded);
    const pass =
      nums.label === decoded.label &&
      nums.values.length === decoded.values.length &&
      nums.values.every((v, i) => v === decoded.values[i]);
    correctness.push({ name: "Numbers", pass });
  } catch (e) {
    correctness.push({ name: "Numbers", pass: false });
  }

  // Point3D benchmark
  appendLog("Running Point3D benchmark...");
  await new Promise((r) => setTimeout(r, 10));

  {
    const point = generatePoint3D();
    const cborEncoded = encodePoint3D(point);
    const jsonEncoded = JSON.stringify(point);

    sections.push({
      name: "Point3D",
      description: "Tiny fixed struct (3 f64 values)",
      cborSize: cborEncoded.length,
      jsonSize: jsonEncoded.length,
      encodeCbor: benchmark("cboragen", () => encodePoint3D(point), benchTimeMs),
      encodeJson: benchmark("JSON", () => JSON.stringify(point), benchTimeMs),
      decodeCbor: benchmark("cboragen", () => decodePoint3D(cborEncoded), benchTimeMs),
      decodeJson: benchmark("JSON", () => JSON.parse(jsonEncoded), benchTimeMs),
    });
  }

  // User benchmark
  appendLog("Running User benchmark...");
  await new Promise((r) => setTimeout(r, 10));

  {
    const user = generateUser(42);
    const cborEncoded = encodeUser(user);
    const jsonEncoded = JSON.stringify(user, jsonReplacer);

    sections.push({
      name: "User",
      description: "Medium object with optional nested struct",
      cborSize: cborEncoded.length,
      jsonSize: jsonEncoded.length,
      encodeCbor: benchmark("cboragen", () => encodeUser(user), benchTimeMs),
      encodeJson: benchmark("JSON", () => JSON.stringify(user, jsonReplacer), benchTimeMs),
      decodeCbor: benchmark("cboragen", () => decodeUser(cborEncoded), benchTimeMs),
      decodeJson: benchmark("JSON", () => JSON.parse(jsonEncoded, jsonReviver), benchTimeMs),
    });
  }

  // Message benchmark
  appendLog("Running Message benchmark...");
  await new Promise((r) => setTimeout(r, 10));

  {
    const message = generateMessage(1);
    const cborEncoded = encodeMessage(message);
    const jsonEncoded = JSON.stringify(message, jsonReplacer);

    sections.push({
      name: "Message",
      description: "Complex nested object with arrays of users and attachments",
      cborSize: cborEncoded.length,
      jsonSize: jsonEncoded.length,
      encodeCbor: benchmark("cboragen", () => encodeMessage(message), benchTimeMs),
      encodeJson: benchmark("JSON", () => JSON.stringify(message, jsonReplacer), benchTimeMs),
      decodeCbor: benchmark("cboragen", () => decodeMessage(cborEncoded), benchTimeMs),
      decodeJson: benchmark("JSON", () => JSON.parse(jsonEncoded, jsonReviver), benchTimeMs),
    });
  }

  // PointCloud benchmark
  appendLog("Running PointCloud benchmark...");
  await new Promise((r) => setTimeout(r, 10));

  {
    const cloud = generatePointCloud(1000);
    const cborEncoded = encodePointCloud(cloud);
    const jsonEncoded = JSON.stringify(cloud);

    sections.push({
      name: "PointCloud (1000 points)",
      description: "Array of 1000 Point3D structs",
      cborSize: cborEncoded.length,
      jsonSize: jsonEncoded.length,
      encodeCbor: benchmark("cboragen", () => encodePointCloud(cloud), benchTimeMs),
      encodeJson: benchmark("JSON", () => JSON.stringify(cloud), benchTimeMs),
      decodeCbor: benchmark("cboragen", () => decodePointCloud(cborEncoded), benchTimeMs),
      decodeJson: benchmark("JSON", () => JSON.parse(jsonEncoded), benchTimeMs),
    });
  }

  // Numbers benchmark
  appendLog("Running Numbers benchmark...");
  await new Promise((r) => setTimeout(r, 10));

  {
    const nums = generateNumbers(10000);
    const cborEncoded = encodeNumbers(nums);
    const jsonEncoded = JSON.stringify(nums);

    sections.push({
      name: "Numbers (10000 f64)",
      description: "Array of 10000 f64 values",
      cborSize: cborEncoded.length,
      jsonSize: jsonEncoded.length,
      encodeCbor: benchmark("cboragen", () => encodeNumbers(nums), benchTimeMs),
      encodeJson: benchmark("JSON", () => JSON.stringify(nums), benchTimeMs),
      decodeCbor: benchmark("cboragen", () => decodeNumbers(cborEncoded), benchTimeMs),
      decodeJson: benchmark("JSON", () => JSON.parse(jsonEncoded), benchTimeMs),
    });
  }

  appendLog("Done!");
  renderResults(correctness, sections);
}

// ============================================================================
// Event handlers
// ============================================================================

runBtn.addEventListener("click", async () => {
  runBtn.disabled = true;
  runQuickBtn.disabled = true;
  resultsEl.innerHTML = "";

  try {
    await runBenchmarks(false);
  } finally {
    runBtn.disabled = false;
    runQuickBtn.disabled = false;
  }
});

runQuickBtn.addEventListener("click", async () => {
  runBtn.disabled = true;
  runQuickBtn.disabled = true;
  resultsEl.innerHTML = "";

  try {
    await runBenchmarks(true);
  } finally {
    runBtn.disabled = false;
    runQuickBtn.disabled = false;
  }
});

// Show browser info
const browserInfo = `${navigator.userAgent.split(") ")[0].split("(")[1] || "Unknown browser"}`;
log(`Ready. Browser: ${browserInfo}\nClick "Run Benchmarks" to start.`);
