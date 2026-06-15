<?php
/* Read-only tang health (reachability + thumbprint match). No secrets. */
require __DIR__ . '/helpers.php';
cau_run_json([CAU_SCRIPTS . '/health-check.sh']);
