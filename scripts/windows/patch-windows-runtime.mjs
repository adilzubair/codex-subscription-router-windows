#!/usr/bin/env node

import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { parseArgs } from "node:util";

import { createPackageWithOptions, extractAll } from "@electron/asar";

function replaceOnce(text, anchor, replacement, label) {
  const count = text.split(anchor).length - 1;
  if (count !== 1) {
    throw new Error(`expected one ${label} anchor, found ${count}`);
  }
  return text.replace(anchor, replacement);
}

function occurrenceCount(text, anchor) {
  return text.split(anchor).length - 1;
}

function listFiles(root) {
  const files = [];
  if (!fs.existsSync(root)) return files;
  const visit = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(absolute);
      else if (entry.isFile()) files.push(path.relative(root, absolute).replaceAll("\\", "/"));
    }
  };
  visit(root);
  return files.sort();
}

function sameList(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

const { values } = parseArgs({
  options: {
    resources: { type: "string" },
    component: { type: "string" },
    token: { type: "string" },
    port: { type: "string" },
  },
});

if (!values.resources || !values.component || !values.token || !values.port) {
  throw new Error("--resources, --component, --token, and --port are required");
}
if (!/^[0-9a-f]{64}$/.test(values.token)) {
  throw new Error("the control token must be 64 lowercase hexadecimal characters");
}
const port = Number(values.port);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("the control port must be between 1 and 65535");
}

const resources = path.resolve(values.resources);
const componentPath = path.resolve(values.component);
const asarPath = path.join(resources, "app.asar");
const originalUnpacked = path.join(resources, "app.asar.unpacked");
if (!fs.existsSync(asarPath) || !fs.existsSync(componentPath)) {
  throw new Error("the Windows runtime or account-menu component is missing");
}

const temporaryRoot = path.join(
  resources,
  `.codex-router-patch-${process.pid}-${Date.now()}`,
);
const extracted = path.join(temporaryRoot, "extracted");
const outputAsar = path.join(temporaryRoot, "app.asar");

try {
  fs.mkdirSync(temporaryRoot, { recursive: false });
  extractAll(asarPath, extracted);

  const webview = path.join(extracted, "webview");
  const indexPath = path.join(webview, "index.html");
  const bundleDirectory = path.join(webview, "assets");
  const bundles = fs
    .readdirSync(bundleDirectory)
    .filter((name) => /^app-initial-.*\.js$/.test(name));
  if (bundles.length !== 1) {
    throw new Error(`expected one app-initial bundle, found ${bundles.length}`);
  }
  const bundlePath = path.join(bundleDirectory, bundles[0]);

  let index = fs.readFileSync(indexPath, "utf8");
  const loopback = `http://127.0.0.1:${port}`;
  if (!index.includes(loopback)) {
    index = replaceOnce(
      index,
      "connect-src &#39;self&#39;",
      `connect-src &#39;self&#39; ${loopback}`,
      "renderer CSP connect-src",
    );
    fs.writeFileSync(indexPath, index, "utf8");
  }

  let component = fs.readFileSync(componentPath, "utf8");
  component = component
    .replaceAll("__CODEX_MUX_CONTROL_PORT__", String(port))
    .replaceAll("__CODEX_MUX_CONTROL_TOKEN__", values.token);
  if (component.includes("__CODEX_MUX_")) {
    throw new Error("an account-menu placeholder was not replaced");
  }

  let bundle = fs.readFileSync(bundlePath, "utf8");
  const layouts = [
    {
      name: "26.810",
      componentAnchor: "function ncl(e)",
      usageAnchor: "usageItems:wt",
      usageReplacement: "usageItems:(0,e7.jsx)(CodexMuxWindowsAccountMenu,{})",
      openAnchor: "onOpenChange:l,children:P",
      openReplacement:
        "onOpenChange:CodexMuxWindowsProfileMenuOpenChange(l),children:P",
    },
    {
      name: "26.814",
      componentAnchor: "function HFl(e)",
      usageAnchor: "usageItems:Ct,workspaceSettingsRightIcon:N",
      usageReplacement:
        "usageItems:(0,d7.jsx)(CodexMuxWindowsAccountMenu,{}),workspaceSettingsRightIcon:N",
      openAnchor: "onOpenChange:l,children:P",
      openReplacement:
        "onOpenChange:CodexMuxWindowsProfileMenuOpenChange(l),children:P",
      symbols: { react: "QFl", jsx: "d7", menu: "hI" },
    },
  ];
  const matchingLayouts = layouts.filter(
    (layout) =>
      occurrenceCount(bundle, layout.componentAnchor) === 1 &&
      occurrenceCount(bundle, layout.usageAnchor) === 1 &&
      occurrenceCount(bundle, layout.openAnchor) === 1,
  );
  if (matchingLayouts.length !== 1) {
    throw new Error(
      `expected one supported profile-menu layout, found ${matchingLayouts.length}`,
    );
  }
  const layout = matchingLayouts[0];
  if (layout.symbols) {
    component = component
      .replaceAll("fcl.", `${layout.symbols.react}.`)
      .replaceAll("e7.", `${layout.symbols.jsx}.`)
      .replaceAll("yH.", `${layout.symbols.menu}.`);
  }
  bundle = replaceOnce(
    bundle,
    layout.componentAnchor,
    `${component}\n${layout.componentAnchor}`,
    "profile menu component",
  );
  bundle = replaceOnce(
    bundle,
    layout.usageAnchor,
    layout.usageReplacement,
    "profile usage slot",
  );
  bundle = replaceOnce(
    bundle,
    layout.openAnchor,
    layout.openReplacement,
    "profile menu open handler",
  );
  fs.writeFileSync(bundlePath, bundle, "utf8");

  const syntaxCheck = spawnSync(process.execPath, ["--check", bundlePath], {
    encoding: "utf8",
  });
  if (syntaxCheck.status !== 0) {
    throw new Error(`patched renderer syntax check failed: ${syntaxCheck.stderr.trim()}`);
  }

  await createPackageWithOptions(extracted, outputAsar, {
    unpack: "**/*.node",
    unpackDir:
      "node_modules/{@worklouder/device-kit-oai/node_modules/{@serialport/bindings-cpp/build/Release,node-hid/build/Release},better-sqlite3/{build,lib,node_modules},node-pty/{build,lib}}",
    dot: true,
  });

  const outputUnpacked = `${outputAsar}.unpacked`;
  const originalFiles = listFiles(originalUnpacked);
  const outputFiles = listFiles(outputUnpacked);
  if (!sameList(originalFiles, outputFiles)) {
    const missing = originalFiles.filter((file) => !outputFiles.includes(file));
    const extra = outputFiles.filter((file) => !originalFiles.includes(file));
    throw new Error(
      `native-module layout changed (official ${originalFiles.length}, repacked ${outputFiles.length}, missing ${missing.join(",") || "none"}, extra ${extra.join(",") || "none"})`,
    );
  }

  fs.copyFileSync(outputAsar, asarPath);
  fs.cpSync(outputUnpacked, originalUnpacked, { recursive: true, force: true });
  const patchedHash = createHash("sha256").update(fs.readFileSync(asarPath)).digest("hex");
  process.stdout.write(
    `Patched Windows native menu for layout ${layout.name} (${patchedHash.slice(0, 12)}).\n`,
  );
} finally {
  if (fs.existsSync(temporaryRoot)) {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}
