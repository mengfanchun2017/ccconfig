#!/usr/bin/env node
/**
 * settings.json 智能同步脚本
 * 只同步配置部分，保留本地状态部分
 */

const fs = require('fs');
const path = require('path');

// 配置部分的键名 - 这些需要同步
const CONFIG_KEYS = [
  'env',
  'permissions',
  'extraKnownMarketplaces',
  'enabledPlugins',
  'mcpServers'
];

// 本地状态部分的键名 - 这些保留本地值
const STATE_KEYS = [
  'model',  // 模型是本地偏好，不同步
  'numStartups',
  'installMethod',
  'hasSeenTasksHint',
  'tipsHistory',
  'promptQueueUseCount',
  'showExpandedTodos',
  'cachedChromeExtensionInstalled',
  'firstStartTime',
  'hasCompletedOnboarding',
  'opusProMigrationComplete',
  'sonnet1m45MigrationComplete',
  'userID',
  'projects',
  'lastReleaseNotesSeen',
  'officialMarketplaceAutoInstallAttempted',
  'officialMarketplaceAutoInstalled',
  'toolUsage',
  'skillUsage',
  'clientDataCache',
  'showSpinnerTree',
  'lastPlanModeUse',
  'githubRepoPaths'
];

function mergeSettings(source, target) {
  const result = { ...target };

  // 复制配置部分（从 source 到 result）
  for (const key of CONFIG_KEYS) {
    if (source[key] !== undefined) {
      result[key] = source[key];
    }
  }

  // 确保本地状态部分存在（从 target 保留）
  for (const key of STATE_KEYS) {
    if (target[key] !== undefined) {
      result[key] = target[key];
    }
  }

  return result;
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(content);
  } catch (e) {
    console.error(`❌ 读取文件失败: ${filePath}`);
    console.error(e.message);
    return null;
  }
}

function writeJson(filePath, data) {
  try {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (e) {
    console.error(`❌ 写入文件失败: ${filePath}`);
    console.error(e.message);
    return false;
  }
}

function pullSettings() {
  console.log('📥 拉取 settings.json 配置...');

  const repoPath = path.join(__dirname, '..', 'config', 'settings.json');
  const localPath = path.join(
    process.env.USERPROFILE || process.env.HOME,
    '.claude',
    'settings.json'
  );

  const repoSettings = readJson(repoPath);
  const localSettings = readJson(localPath);

  if (!repoSettings) {
    console.log('⚠️  仓库中没有 settings.json，跳过');
    return false;
  }

  let mergedSettings;
  if (localSettings) {
    console.log('🔄 合并配置（保留本地状态）...');
    mergedSettings = mergeSettings(repoSettings, localSettings);
  } else {
    console.log('📄 本地没有 settings.json，直接复制...');
    mergedSettings = repoSettings;
  }

  if (writeJson(localPath, mergedSettings)) {
    console.log('✅ settings.json 已同步');
    return true;
  }
  return false;
}

function pushSettings() {
  console.log('📤 推送 settings.json 配置...');

  const localPath = path.join(
    process.env.USERPROFILE || process.env.HOME,
    '.claude',
    'settings.json'
  );
  const repoPath = path.join(__dirname, '..', 'config', 'settings.json');

  const localSettings = readJson(localPath);
  const repoSettings = readJson(repoPath);

  if (!localSettings) {
    console.log('❌ 本地没有 settings.json');
    return false;
  }

  // 提取配置部分
  const configOnly = {};
  for (const key of CONFIG_KEYS) {
    if (localSettings[key] !== undefined) {
      configOnly[key] = localSettings[key];
    }
  }

  // 如果仓库有 settings.json，保留它的状态部分（但实际上我们只存配置部分）
  let toSave;
  if (repoSettings) {
    toSave = { ...repoSettings, ...configOnly };
  } else {
    toSave = configOnly;
  }

  if (writeJson(repoPath, toSave)) {
    console.log('✅ settings.json 配置已提取到仓库');
    return true;
  }
  return false;
}

function main() {
  const command = process.argv[2];

  console.log('========================================');
  console.log('  settings.json 智能同步');
  console.log('========================================');
  console.log();

  if (command === 'pull') {
    pullSettings();
  } else if (command === 'push') {
    pushSettings();
  } else {
    console.log('用法:');
    console.log('  node sync-settings.js pull  - 从仓库拉取配置到本地');
    console.log('  node sync-settings.js push  - 从本地推送配置到仓库');
    console.log();
    console.log('同步的配置项:', CONFIG_KEYS.join(', '));
    console.log('保留的本地状态:', STATE_KEYS.slice(0, 5).join(', '), '...');
  }

  console.log();
}

main();
