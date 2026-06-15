<?php
/* Read-only status for the dashboard (config + per-device bind state). No secrets. */
require __DIR__ . '/helpers.php';
cau_run_json([CAU_SCRIPTS . '/status.sh']);
