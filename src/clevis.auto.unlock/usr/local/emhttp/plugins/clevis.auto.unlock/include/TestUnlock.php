<?php
/* Dry-run test-unlock of all devices. POST: csrf_token. Changes nothing. */
require __DIR__ . '/helpers.php';
cau_require_post();
cau_run_json([CAU_SCRIPTS . '/test-unlock.sh']);
