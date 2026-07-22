#!/usr/bin/env node
// Validate a generated change before propose, dispatch, or review transitions.

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const valueOf = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : "";
};
const changeId = valueOf("--change");
const type = valueOf("--type");
const phase = valueOf("--phase") || "propose";
const root = path.resolve(valueOf("--root") || process.cwd());
const failures = [];

if (!/^[a-z0-9][a-z0-9-]*$/.test(changeId)) failures.push("invalid --change");
if (!["feature", "bug", "chore", "hotfix"].includes(type)) failures.push("invalid --type");
if (!["propose", "dispatch", "review", "premerge"].includes(phase)) failures.push("invalid --phase");

const changeDir = path.join(root, "openspec/changes", changeId);
const requiredFiles = ["proposal.md", "design.md", "tasks.md", "_DIR.md"];
for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(changeDir, file))) failures.push(`missing ${file}`);
}

function walkMarkdown(directory) {
  if (!fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...walkMarkdown(entryPath));
    else if (entry.name.endsWith(".md")) result.push(entryPath);
  }
  return result;
}

const specsDir = path.join(changeDir, "specs");
const specFiles = walkMarkdown(specsDir);
const deltaFiles = specFiles.filter((file) => !/[\\/]README\.md$/.test(file) && !/[\\/]_DIR\.md$/.test(file));
const emptyMarker = path.join(specsDir, "README.md");

if (type === "feature" && !deltaFiles.length) failures.push("feature requires at least one delta spec");
if (type !== "feature" && !deltaFiles.length) {
  const marker = fs.existsSync(emptyMarker) ? fs.readFileSync(emptyMarker, "utf8") : "";
  if (!/^delta-specs:\s*none\s*$/mi.test(marker)) {
    failures.push("optional empty specs require specs/README.md with delta-specs: none");
  }
  if (!/^reason:\s*\S.*$/mi.test(marker)) {
    failures.push("optional empty specs require a non-empty reason");
  }
}

const boundaryPattern = /边界|异常|失败|无效|拒绝|错误|缺失|为空|超限|不可用|超时|boundary|invalid|error|fail(?:ure)?|denied|missing|empty|unavailable|timeout/i;
for (const file of deltaFiles) {
  const markdown = fs.readFileSync(file, "utf8");
  const requirementMatches = [...markdown.matchAll(/^#{3,6}\s+(?:REQ|Requirement|需求)\s*[:：]\s*(.+)$/gmi)];
  if (!requirementMatches.length) {
    failures.push(`${path.relative(root, file)} has no requirement headings`);
    continue;
  }

  const deltaHeadings = [...markdown.matchAll(/^##\s+(ADDED|MODIFIED|REMOVED)\s+Requirements?/gmi)];
  for (let index = 0; index < requirementMatches.length; index += 1) {
    const requirement = requirementMatches[index];
    const deltaKind = deltaHeadings.filter((heading) => heading.index < requirement.index).at(-1)?.[1]?.toUpperCase();
    if (deltaKind === "REMOVED") continue;
    const end = requirementMatches[index + 1]?.index ?? markdown.length;
    const block = markdown.slice(requirement.index, end);
    const scenarioMatches = [...block.matchAll(/^(?:#{2,6}\s+)?(?:\*\*)?(?:Scenario|场景)\s*[:：]\s*([^\n*]+)(?:\*\*)?\s*$/gmi)];
    if (scenarioMatches.length < 2) {
      failures.push(`${path.relative(root, file)} requirement "${requirement[1]}" needs normal and boundary scenarios`);
      continue;
    }
    let hasNormal = false;
    let hasBoundary = false;
    for (let scenarioIndex = 0; scenarioIndex < scenarioMatches.length; scenarioIndex += 1) {
      const scenario = scenarioMatches[scenarioIndex];
      const scenarioEnd = scenarioMatches[scenarioIndex + 1]?.index ?? block.length;
      const scenarioBlock = block.slice(scenario.index, scenarioEnd);
      for (const keyword of ["Given", "When", "Then"]) {
        if (!new RegExp(`(?:^|[-*]\\s*)${keyword}\\b`, "mi").test(scenarioBlock)) {
          failures.push(`${path.relative(root, file)} scenario "${scenario[1]}" missing ${keyword}`);
        }
      }
      if (boundaryPattern.test(`${scenario[1]}\n${scenarioBlock}`)) hasBoundary = true;
      else hasNormal = true;
    }
    if (!hasNormal || !hasBoundary) {
      failures.push(`${path.relative(root, file)} requirement "${requirement[1]}" must label one normal and one boundary/error scenario`);
    }
  }
}

const tasksPath = path.join(changeDir, "tasks.md");
if (fs.existsSync(tasksPath)) {
  const tasks = fs.readFileSync(tasksPath, "utf8");
  if (tasks.split("\n").length > 300) failures.push("tasks.md exceeds 300 lines");
  const status = tasks.match(/^status:\s*(\w+)/m)?.[1];
  const allowedByPhase = {
    propose: ["ready"],
    dispatch: ["ready", "executing", "review"],
    review: ["review", "done"],
    premerge: ["review"],
  };
  if (!allowedByPhase[phase].includes(status)) failures.push(`tasks status ${status || "missing"} invalid for ${phase}`);

  const headings = [...tasks.matchAll(/^##\s+(.+)$/gm)].map((match) => ({ name: match[1], index: match.index }));
  const terminalNames = headings.slice(-3).map((heading) => heading.name);
  if (terminalNames.join("|") !== "文档与分形同步|Verify|归档") {
    failures.push("terminal task groups must be 文档与分形同步 → Verify → 归档");
  }

  for (let index = 0; index < headings.length; index += 1) {
    const heading = headings[index];
    const end = headings[index + 1]?.index ?? tasks.length;
    const section = tasks.slice(heading.index, end);
    const comment = section.match(/<!--([\s\S]*?)-->/)?.[1] || "";
    if (!comment.includes("执行模式:")) failures.push(`${heading.name} missing execution mode`);
    const groupStatus = comment.match(/status:\s*(\w+)/)?.[1];
    if (!groupStatus || !["pending", "executing", "done"].includes(groupStatus)) {
      failures.push(`${heading.name} has invalid group status`);
    }
    const openTasks = [...section.matchAll(/^- \[ \]\s+.+$/gm)];
    const checkedTasks = [...section.matchAll(/^- \[[xX]\]\s+.+$/gm)];
    if (!openTasks.length && !checkedTasks.length) failures.push(`${heading.name} has no checklist tasks`);
    if (groupStatus === "pending" && checkedTasks.length) failures.push(`${heading.name} pending group has checked tasks`);
    if (groupStatus === "done" && openTasks.length) failures.push(`${heading.name} done group has unchecked tasks`);
    if (comment.includes("执行模式: auto")) {
      for (const field of ["claim-id:", "claimed-at:", "heartbeat-at:"]) {
        if (!comment.includes(field)) failures.push(`${heading.name} missing ${field}`);
      }
      const claimId = comment.match(/claim-id:\s*([^|\s]+)/)?.[1];
      const claimedAt = comment.match(/claimed-at:\s*([^|\s]+)/)?.[1];
      const heartbeatAt = comment.match(/heartbeat-at:\s*([^|\s]+)/)?.[1];
      const isIsoTimestamp = (value) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value || "");
      if (groupStatus === "executing") {
        if (!claimId || claimId === "none") failures.push(`${heading.name} executing without claim-id`);
        if (!isIsoTimestamp(claimedAt)) failures.push(`${heading.name} has invalid claimed-at`);
        if (!isIsoTimestamp(heartbeatAt)) failures.push(`${heading.name} has invalid heartbeat-at`);
      } else if ([claimId, claimedAt, heartbeatAt].some((value) => value !== "none")) {
        failures.push(`${heading.name} ${groupStatus} must clear claim fields to none`);
      }
      if (phase === "propose" && groupStatus !== "pending") failures.push(`${heading.name} must be pending at propose`);
      if (["review", "premerge"].includes(phase) && groupStatus !== "done") failures.push(`${heading.name} is not done at review`);
    }
  }

  if (phase === "premerge") {
    for (const terminalName of ["文档与分形同步", "Verify"]) {
      const terminal = headings.find((heading) => heading.name === terminalName);
      if (terminal) {
        const end = headings[headings.indexOf(terminal) + 1]?.index ?? tasks.length;
        const statusValue = tasks.slice(terminal.index, end).match(/status:\s*(\w+)/)?.[1];
        if (statusValue !== "done") failures.push(`${terminalName} must be done before merge`);
      }
    }
  }
}

if (failures.length) {
  for (const failure of [...new Set(failures)]) console.error(`FAIL: ${failure}`);
  process.exit(1);
}
console.log(`Change ${changeId} is valid for ${phase}.`);
