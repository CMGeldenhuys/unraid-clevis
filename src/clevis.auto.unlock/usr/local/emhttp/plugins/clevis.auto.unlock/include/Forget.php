<?php
/* Remove the sealed passphrase and disable auto-unlock. POST: csrf_token.
 * Does not touch any LUKS header. */
require __DIR__ . '/helpers.php';
cau_require_csrf();
cau_run_json([CAU_SCRIPTS . '/forget.sh']);
