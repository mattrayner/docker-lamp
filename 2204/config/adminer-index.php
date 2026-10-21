<?php
declare(strict_types=1);

// Adminer still validates and authenticates every submitted credential. This
// wrapper only supplies a convenient local database host when none is chosen.
if (!isset($_GET['server']) || $_GET['server'] === '') {
    $_GET['server'] = 'localhost';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!isset($_POST['auth']) || !is_array($_POST['auth'])) {
        $_POST['auth'] = [];
    }

    if (!isset($_POST['auth']['server']) || $_POST['auth']['server'] === '') {
        $_POST['auth']['server'] = 'localhost';
    }
}

require __DIR__ . '/adminer.php';
