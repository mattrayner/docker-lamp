<?php
declare(strict_types=1);

header('Content-Type: text/plain; charset=UTF-8');

/** @param callable(): bool $check */
function report_check(string $name, callable $check): bool
{
    try {
        $passed = $check();
    } catch (Throwable) {
        $passed = false;
    }

    echo $name . '=' . ($passed ? 'ok' : 'failed') . "\n";
    return $passed;
}

$passed = true;
echo 'upload_max_filesize=' . ini_get('upload_max_filesize') . "\n";
echo 'post_max_size=' . ini_get('post_max_size') . "\n";
echo 'timezone=' . ini_get('date.timezone') . "\n";

$passed = report_check('apcu', static function (): bool {
    $key = 'docker_lamp_apcu_' . bin2hex(random_bytes(8));
    return apcu_enabled() && apcu_store($key, 'stored-value') && apcu_fetch($key) === 'stored-value';
}) && $passed;

$passed = report_check('curl', static function (): bool {
    $handle = curl_init('http://127.0.0.1/static-check.txt');
    curl_setopt_array($handle, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_TIMEOUT => 5,
    ]);
    $body = curl_exec($handle);
    $status = curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
    curl_close($handle);

    return $status === 200 && $body === "docker-lamp static fixture\n";
}) && $passed;

$passed = report_check('gd', static function (): bool {
    $image = imagecreatetruecolor(2, 3);
    ob_start();
    imagepng($image);
    $png = ob_get_clean();
    imagedestroy($image);
    $parsed = imagecreatefromstring($png);
    $valid = imagesx($parsed) === 2 && imagesy($parsed) === 3;
    imagedestroy($parsed);

    return $valid;
}) && $passed;

$passed = report_check('mbstring', static function (): bool {
    return mb_strlen('😀 café', 'UTF-8') === 6 && mb_strtoupper('é', 'UTF-8') === 'É';
}) && $passed;

$passed = report_check('xml', static function (): bool {
    $xml = simplexml_load_string('<root><item>✓</item></root>');
    return $xml !== false && (string) $xml->item === '✓';
}) && $passed;

$passed = report_check('zip', static function (): bool {
    $path = tempnam(sys_get_temp_dir(), 'docker-lamp-zip-');
    $zip = new ZipArchive();
    if ($zip->open($path, ZipArchive::OVERWRITE) !== true) {
        return false;
    }
    $zip->addFromString('check.txt', 'zip-content');
    $zip->close();
    $zip = new ZipArchive();
    $opened = $zip->open($path) === true;
    $contents = $opened ? $zip->getFromName('check.txt') : false;
    $zip->close();
    unlink($path);

    return $contents === 'zip-content';
}) && $passed;

$password = getenv('MYSQL_ADMIN_PASS');
$passed = report_check('mysqli', static function () use ($password): bool {
    $mysqli = mysqli_init();
    if (!$mysqli || !mysqli_real_connect($mysqli, '127.0.0.1', 'admin', $password, null, 3306)) {
        return false;
    }
    $result = mysqli_query($mysqli, 'SELECT 85 AS answer');
    $row = $result ? mysqli_fetch_assoc($result) : null;
    mysqli_close($mysqli);

    return $row !== null && $row['answer'] === '85';
}) && $passed;

$passed = report_check('pdo_mysql', static function () use ($password): bool {
    $pdo = new PDO(
        'mysql:host=127.0.0.1;port=3306',
        'admin',
        $password,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    return (int) $pdo->query('SELECT 85')->fetchColumn() === 85;
}) && $passed;

if (!$passed) {
    http_response_code(500);
}
