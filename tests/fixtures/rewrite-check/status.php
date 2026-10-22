<?php

$required = ['apcu', 'curl', 'gd', 'mbstring', 'mysqli', 'pdo_mysql', 'xml', 'zip'];
foreach ($required as $extension) {
    if (!extension_loaded($extension)) {
        http_response_code(500);
        echo "missing={$extension}\n";
        exit(1);
    }
}

echo 'php=' . PHP_VERSION . "\n";
echo "extensions=ok\n";
