<?php
/* Seal the array passphrase to tang. POST: url (optional), passphrase, csrf_token.
 * The passphrase travels to seal.sh on STDIN only. */
require __DIR__ . '/helpers.php';
cau_require_post();

$url  = (string)($_POST['url'] ?? '');
$pass = (string)($_POST['passphrase'] ?? '');

if ($url !== '' && !cau_valid_url($url)) cau_json(['ok' => false, 'error' => 'Invalid tang URL']);
if ($pass === '')                        cau_json(['ok' => false, 'error' => 'Passphrase required']);

$args = [CAU_SCRIPTS . '/seal.sh'];
if ($url !== '') $args[] = $url;
cau_run_json($args, $pass);
