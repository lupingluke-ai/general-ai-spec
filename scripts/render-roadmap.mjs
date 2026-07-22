#!/usr/bin/env node
// Deterministically render roadmap AUTO sections from modules and backlog.

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const mode = args.includes("--write") ? "write" : args.includes("--check") ? "check" : "";
const rootIndex = args.indexOf("--root");
const root = path.resolve(rootIndex >= 0 ? args[rootIndex + 1] : process.cwd());

if (!mode) {
  console.error("Usage: render-roadmap.mjs (--check|--write) [--root <project>]");
  process.exit(2);
}

const roadmapPath = path.join(root, "design/roadmap.md");
const backlogPath = path.join(root, "product/backlog.md");
const modulesDir = path.join(root, "design/modules");

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function frontmatter(markdown) {
  const match = markdown.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};
  const result = {};
  for (const line of match[1].split("\n")) {
    const field = line.match(/^([a-z-]+):\s*(.*)$/i);
    if (field) result[field[1]] = field[2].replace(/\s+#.*$/, "").trim();
  }
  return result;
}

function parseList(value = "") {
  const match = value.match(/^\[(.*)]$/);
  if (!match || !match[1].trim()) return [];
  return match[1].split(",").map((item) => item.trim()).filter(Boolean);
}

function cell(value) {
  return String(value || "—").replaceAll("|", "\\|").replaceAll("\n", " ");
}

const moduleFiles = fs.existsSync(modulesDir)
  ? fs.readdirSync(modulesDir).filter((name) => /^M-\d+-.+\.md$/.test(name)).sort()
  : [];

const modules = moduleFiles.map((file) => {
  const markdown = read(path.join(modulesDir, file));
  const meta = frontmatter(markdown);
  const heading = markdown.match(/^#\s+(M-\d+)\s+(.+)$/m);
  return {
    id: meta.id || heading?.[1] || file.match(/^(M-\d+)/)?.[1],
    name: heading?.[2] || meta.slug || file,
    status: meta.status || "planning",
    created: meta.created || "—",
    dependsOn: parseList(meta["depends-on"]),
    file,
  };
}).sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));

const duplicateValues = (values) => [...new Set(values.filter((value, index) => values.indexOf(value) !== index))];
const moduleIds = modules.map((module) => module.id);
if (moduleIds.some((id) => !/^M-\d+$/.test(id || ""))) throw new Error("Every module needs a valid M-NNN id");
const duplicateModuleIds = duplicateValues(moduleIds);
if (duplicateModuleIds.length) throw new Error(`Duplicate module ids: ${duplicateModuleIds.join(", ")}`);
const allowedModuleStatuses = new Set(["planning", "active", "done", "deprecated"]);
for (const module of modules) {
  if (!allowedModuleStatuses.has(module.status)) throw new Error(`Invalid module status for ${module.id}: ${module.status}`);
  for (const dependency of module.dependsOn) {
    if (!moduleIds.includes(dependency)) throw new Error(`Unknown dependency for ${module.id}: ${dependency}`);
    if (dependency === module.id) throw new Error(`Self dependency for ${module.id}`);
  }
}

const visiting = new Set();
const visited = new Set();
const moduleById = new Map(modules.map((module) => [module.id, module]));
function visitModule(id) {
  if (visiting.has(id)) throw new Error(`Module dependency cycle detected at ${id}`);
  if (visited.has(id)) return;
  visiting.add(id);
  for (const dependency of moduleById.get(id).dependsOn) visitModule(dependency);
  visiting.delete(id);
  visited.add(id);
}
for (const id of moduleIds) visitModule(id);

const moduleNames = new Map(modules.map((module) => [module.id, module.name]));
const backlogRows = [];
const backlogLines = read(backlogPath).split("\n");
let columns = null;
for (const line of backlogLines) {
  if (/^\|\s*ID\s*\|/.test(line) && line.includes("模块") && line.includes("阶段")) {
    columns = line.split("|").slice(1, -1).map((value) => value.trim());
    continue;
  }
  if (!columns || !/^\|\s*B-\d+\s*\|/.test(line)) continue;
  const values = line.split("|").slice(1, -1).map((value) => value.trim());
  const row = Object.fromEntries(columns.map((column, index) => [column, values[index] || "—"]));
  backlogRows.push(row);
}

const backlogIds = backlogRows.map((row) => row.ID);
const duplicateBacklogIds = duplicateValues(backlogIds);
if (duplicateBacklogIds.length) throw new Error(`Duplicate backlog ids: ${duplicateBacklogIds.join(", ")}`);
const allowedBacklogStages = new Set(["idea", "exploring", "proposed", "done"]);
for (const row of backlogRows) {
  if (!/^B-\d+$/.test(row.ID || "")) throw new Error(`Invalid backlog id: ${row.ID || "missing"}`);
  if (!allowedBacklogStages.has(row["阶段"])) throw new Error(`Invalid backlog stage for ${row.ID}: ${row["阶段"]}`);
  if (row["模块"] !== "—" && !moduleIds.includes(row["模块"])) {
    throw new Error(`Unknown module for ${row.ID}: ${row["模块"]}`);
  }
}

const architecture = [
  "## 功能架构",
  "",
  "| 模块 ID | 模块名 | 状态 | 模块设计 | 依赖 | 创建时间 |",
  "|---|---|---|---|---|---|",
  ...modules.map((module) =>
    `| ${cell(module.id)} | ${cell(module.name)} | ${cell(module.status)} | [${cell(module.file)}](modules/${module.file}) | ${cell(module.dependsOn.join(", "))} | ${cell(module.created)} |`
  ),
];

const dependencies = [
  "## 模块依赖",
  "",
  "```text",
  ...(modules.length
    ? modules.map((module) => `${module.id} -> ${module.dependsOn.length ? module.dependsOn.join(", ") : "none"}`)
    : ["none"]),
  "```",
];

const stageIcons = { idea: "💡", exploring: "🔎", proposed: "📝", done: "✅" };
const groupedRows = new Map();
for (const row of backlogRows) {
  const moduleId = row["模块"] || "—";
  if (!groupedRows.has(moduleId)) groupedRows.set(moduleId, []);
  groupedRows.get(moduleId).push(row);
}

const progress = ["## 开发进度", ""];
for (const moduleId of [...groupedRows.keys()].sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))) {
  progress.push(`### ${moduleId} ${moduleNames.get(moduleId) || "未归类"}`, "");
  for (const row of groupedRows.get(moduleId)) {
    progress.push(`- ${stageIcons[row["阶段"]] || "❓"} ${row.ID} ${row["需求"]}`);
  }
  progress.push("");
}
if (!backlogRows.length) progress.push("（暂无 backlog 条目）", "");

function replaceSection(markdown, name, lines) {
  const start = `<!-- AUTO:${name}_START`;
  const end = `<!-- AUTO:${name}_END -->`;
  const startIndex = markdown.indexOf(start);
  const startClose = markdown.indexOf("-->", startIndex);
  const endIndex = markdown.indexOf(end, startClose);
  if (startIndex < 0 || startClose < 0 || endIndex < 0) {
    throw new Error(`Missing AUTO markers for ${name}`);
  }
  return `${markdown.slice(0, startClose + 3)}\n${lines.join("\n").trimEnd()}\n\n${markdown.slice(endIndex)}`;
}

const original = read(roadmapPath);
let rendered = replaceSection(original, "ARCHITECTURE", architecture);
rendered = replaceSection(rendered, "DEPENDENCIES", dependencies);
rendered = replaceSection(rendered, "PROGRESS", progress);
if (!rendered.endsWith("\n")) rendered += "\n";

if (mode === "check") {
  if (rendered !== original) {
    console.error("Roadmap AUTO sections are stale. Run render-roadmap.mjs --write.");
    process.exit(1);
  }
  console.log("Roadmap AUTO sections are current.");
} else {
  fs.writeFileSync(roadmapPath, rendered);
  console.log(`Rendered ${path.relative(root, roadmapPath)}.`);
}
