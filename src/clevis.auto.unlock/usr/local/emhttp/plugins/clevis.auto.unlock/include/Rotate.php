<?php
/* Re-pin to the tang server's current key and regenerate bindings.
 * POST: url (optional), csrf_token. */
require __DIR__ . '/helpers.php';
cau_require_csrf();

$url = (string)($_POST['url'] ?? '');
if ($url !== '' && !cau_valid_url($url)) cau_json(['ok' => false, 'error' => 'Invalid tang URL']);

$args = [CAU_SCRIPTS . '/rotate.sh'];
if ($url !== '') $args[] = $url;
cau_run_json($args);
