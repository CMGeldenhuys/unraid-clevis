<?php
/* Shared helpers for the Clevis Auto-Unlock webGUI endpoints.
 *
 * Security:
 *  - every state-changing endpoint calls cau_require_csrf() (token from POST only).
 *  - external commands run via proc_open() with an ARGV ARRAY (never a shell
 *    string), so inputs cannot be used for command injection.
 *  - the passphrase is passed to seal.sh on STDIN only — never in argv, never logged.
 *
 * Output discipline: these endpoints must return ONLY a JSON object. A stray PHP
 * notice/warning printed before the JSON would make the browser's r.json() throw and
 * the button look dead — so we suppress error output and clean the buffer before emit.
 */

error_reporting(0);
ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
ob_start();

const CAU_PLUGIN  = 'clevis.auto.unlock';
const CAU_SCRIPTS = '/usr/local/emhttp/plugins/clevis.auto.unlock/scripts';
/* Full PATH for spawned scripts; php-fpm runs clear_env=yes so we must set it. */
const CAU_PATH    = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

/* Validate the Unraid CSRF token (from /var/local/emhttp/var.ini). POST only. */
function cau_csrf_ok(): bool {
    $var = @parse_ini_file('/var/local/emhttp/var.ini');
    $token = $_POST['csrf_token'] ?? '';
    return !empty($var['csrf_token'])
        && is_string($token)
        && hash_equals((string)$var['csrf_token'], $token);
}

function cau_require_csrf(): void {
    if (!cau_csrf_ok()) {
        http_response_code(403);
        cau_json(['ok' => false, 'error' => 'Invalid or missing CSRF token']);
    }
}

/* Emit exactly one JSON object and stop, discarding any buffered notice output. */
function cau_json($data): void {
    if (ob_get_level() > 0) { ob_clean(); }
    header('Content-Type: application/json');
    echo is_string($data) ? $data : json_encode($data);
    exit;
}

/* Accept only http(s) tang URLs (fully anchored; no trailing newline). */
function cau_valid_url(string $u): bool {
    return (bool)preg_match('#\Ahttps?://[A-Za-z0-9._:\[\]/-]{1,255}\z#', $u);
}

/* Run a script. $argv is an array (no shell). Optional $stdin (passphrase).
 *  - wrapped in `timeout` so a stuck child can NEVER pin a php-fpm worker (a pinned
 *    worker exhausts the pool and 504s the whole webGUI);
 *  - output captured via temp files (not pipes) so a lingering descendant or a full
 *    pipe buffer can't block us;
 *  - a known-good PATH is passed explicitly (alongside lib-common.sh's export).
 * Returns [int $rc, string $stdout, string $stderr]. */
function cau_run(array $argv, ?string $stdin = null, int $timeout = 45): array {
    $cmd   = array_merge(['timeout', '-k', '5', (string)$timeout], $argv);
    $outF  = tmpfile(); $errF = tmpfile();
    $descr = [0 => ['pipe', 'r'], 1 => $outF, 2 => $errF];
    $env   = ['PATH' => CAU_PATH, 'HOME' => '/root'];
    $proc  = proc_open($cmd, $descr, $pipes, null, $env);
    if (!is_resource($proc)) { fclose($outF); fclose($errF); return [127, '', 'proc_open failed']; }
    if ($stdin !== null) fwrite($pipes[0], $stdin);
    fclose($pipes[0]);
    $rc = proc_close($proc);   // returns once `timeout` exits (≤ $timeout + 5s)
    rewind($outF); $out = stream_get_contents($outF); fclose($outF);
    rewind($errF); $err = stream_get_contents($errF); fclose($errF);
    if ($rc === 124 || $rc === 137) $err = trim(($err ? "$err\n" : '') . "timed out after {$timeout}s");
    return [$rc, $out, $err];
}

/* Run a script that emits a JSON object on stdout and relay it (validated). */
function cau_run_json(array $argv, ?string $stdin = null): void {
    [$rc, $out, $err] = cau_run($argv, $stdin);
    $decoded = json_decode(trim($out), true);
    if (is_array($decoded)) { cau_json($decoded); }
    cau_json(['ok' => ($rc === 0), 'error' => trim($err) ?: "exit $rc"]);
}
