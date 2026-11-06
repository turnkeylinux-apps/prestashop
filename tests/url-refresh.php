#!/usr/bin/php
<?php
// Integration regression. Run as www-data only in a disposable shop.
require '/var/www/prestashop/config/config.inc.php';
$db = Db::getInstance();
$htaccess = '/var/www/prestashop/.htaccess';
$originalHtaccess = file_get_contents($htaccess);
$originalMode = fileperms($htaccess) & 0777;
$rows = $db->executeS('SELECT * FROM `' . _DB_PREFIX_ . 'psreassurance` ORDER BY id_psreassurance LIMIT 3');
$urls = $db->executeS('SELECT * FROM `' . _DB_PREFIX_ . 'shop_url` WHERE id_shop_url = 1');
$domains = $db->executeS("SELECT id_configuration, value FROM `" . _DB_PREFIX_ . "configuration` WHERE name IN ('PS_SHOP_DOMAIN', 'PS_SHOP_DOMAIN_SSL')");
function check($condition, $message) {
    if (!$condition) {
        throw new RuntimeException($message);
    }
}
function refresh() {
    $output = [];
    exec('/usr/local/bin/turnkey-prestashop-refresh-urls 2>&1', $output, $status);
    return $status;
}
check(count($rows) === 3 && count($urls) === 1, 'Expected disposable default shop fixtures');
try {
    $domain = 'qa-regression.example.invalid';
    $db->update('shop_url', ['domain' => $domain, 'domain_ssl' => $domain], 'id_shop_url = 1');
    foreach ($domains as $row) {
        $db->update('configuration', ['value' => $domain], 'id_configuration = ' . (int) $row['id_configuration']);
    }
    $bad = '//modules/blockreassurance/views/img/reassurance/pack2/security.svg';
    $db->update('psreassurance', ['icon' => $bad, 'custom_icon' => null], 'id_psreassurance = ' . (int) $rows[0]['id_psreassurance'], 0, true);
    $db->update('psreassurance', ['icon' => 'https://cdn.example.invalid/custom.svg'], 'id_psreassurance = ' . (int) $rows[1]['id_psreassurance']);
    $db->update('psreassurance', ['icon' => $bad, 'custom_icon' => '/custom/upload.svg'], 'id_psreassurance = ' . (int) $rows[2]['id_psreassurance']);
    file_put_contents($htaccess, $originalHtaccess . "\n# TurnKey QA custom rule\n");
    check(refresh() === 0, 'Refresh failed');
    $generated = file_get_contents($htaccess);
    check(str_contains($generated, '#Domain: ' . $domain), 'Generated routes did not follow configured domain');
    check(str_contains($generated, '# TurnKey QA custom rule'), 'Custom htaccess content was lost');
    $updated = $db->executeS('SELECT icon, custom_icon FROM `' . _DB_PREFIX_ . 'psreassurance` ORDER BY id_psreassurance LIMIT 3');
    check($updated[0]['icon'] === substr($bad, 1), 'Malformed bundled icon was not repaired');
    check($updated[1]['icon'] === 'https://cdn.example.invalid/custom.svg', 'Custom remote icon changed');
    check($updated[2]['icon'] === $bad && $updated[2]['custom_icon'] === '/custom/upload.svg', 'Customized row changed');
    check(refresh() === 0 && file_get_contents($htaccess) === $generated, 'Repeat refresh changed generated routes');
    chmod($htaccess, 0444);
    check(refresh() !== 0, 'Unwritable htaccess was reported as success');
    echo "PASS: configured domain, bundled icons, custom icons/rules, repeat and write failure\n";
} finally {
    chmod($htaccess, $originalMode);
    file_put_contents($htaccess, $originalHtaccess);
    foreach ($rows as $row) {
        $db->update('psreassurance', ['icon' => $row['icon'], 'custom_icon' => $row['custom_icon']], 'id_psreassurance = ' . (int) $row['id_psreassurance'], 0, true);
    }
    foreach ($urls as $row) {
        $db->update('shop_url', ['domain' => $row['domain'], 'domain_ssl' => $row['domain_ssl']], 'id_shop_url = ' . (int) $row['id_shop_url']);
    }
    foreach ($domains as $row) {
        $db->update('configuration', ['value' => $row['value']], 'id_configuration = ' . (int) $row['id_configuration']);
    }
}
