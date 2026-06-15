<?php
/* Save non-secret settings. POST: enabled, url, unlock_mode, network_timeout, csrf_token.
 * Preserves the pinned tang thumbprint (set during bind). */
require __DIR__ . '/helpers.php';
cau_require_post();

$cfgFile = '/boot/config/plugins/' . CAU_PLUGIN . '/config.json';
$cfg = is_file($cfgFile) ? (json_decode((string)file_get_contents($cfgFile), true) ?: []) : [];

$url = (string)($_POST['url'] ?? '');
if ($url !== '' && !cau_valid_url($url)) cau_json(['ok' => false, 'error' => 'Invalid tang URL']);

$enabled = in_array((string)($_POST['enabled'] ?? ''), ['true', '1', 'on'], true);
$mode    = ((string)($_POST['unlock_mode'] ?? 'event') === 'go') ? 'go' : 'event';
$timeout = max(5, min(600, (int)($_POST['network_timeout'] ?? 60)));

$cfg['enabled']         = $enabled;
$cfg['unlock_mode']     = $mode;
$cfg['network_timeout'] = $timeout;
$cfg['tang']            = $cfg['tang'] ?? [];
if ($url !== '') $cfg['tang']['url'] = $url;
if (!isset($cfg['tang']['thp'])) $cfg['tang']['thp'] = '';

@mkdir(dirname($cfgFile), 0755, true);
if (file_put_contents($cfgFile, json_encode($cfg, JSON_PRETTY_PRINT) . "\n") === false) {
    cau_json(['ok' => false, 'error' => 'Could not write config']);
}

/* Keep the early-boot go hook in sync with the chosen unlock mode. */
cau_run([CAU_SCRIPTS . '/go-hook.sh', $mode === 'go' ? 'install' : 'remove']);

cau_json(['ok' => true, 'config' => $cfg]);
