#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
db_password=${TKL_TEST_DB_PASS:?TKL_TEST_DB_PASS is required}
base=https://localhost
admin_email=admin@example.invalid
webroot=/var/www/prestashop
cookies=/tmp/tkl-prestashop-cookies.$$
page=/tmp/tkl-prestashop-page.$$
headers=/tmp/tkl-prestashop-headers.$$
form_body=/tmp/tkl-prestashop-form.$$
product_blank=/tmp/tkl-prestashop-product-blank.$$
product_request=/tmp/tkl-prestashop-product-request.$$
product_response=/tmp/tkl-prestashop-product-response.$$
product_read=/tmp/tkl-prestashop-product-read.$$
adminer_cookies=/tmp/tkl-prestashop-adminer-cookies.$$
updater_output=/tmp/tkl-prestashop-updater.$$
channel_metadata=/tmp/tkl-prestashop-channel.$$
apt_policy=/tmp/tkl-prestashop-apt-policy.$$
product_id=
product_status=
webservice_id=
webservice_configured=0
ws_enabled=
ws_enabled_exists=

report_error() {
    printf 'test_failure line=%s status=%s\n' "$1" "$2" >&2
    exit "$2"
}
trap 'report_error "$LINENO" "$?"' ERR

db_scalar() {
    mariadb --batch --skip-column-names prestashop --execute "$1"
}

clear_app_cache() {
    su -p -s /bin/sh -c \
        'php /var/www/prestashop/bin/console cache:clear --no-warmup --env=prod' \
        www-data >/dev/null
}

cleanup() {
    if [[ -n $product_id && -n $webservice_id ]]; then
        curl --insecure --silent --show-error --user "$api_key:" \
            --request DELETE "$base/api/products/$product_id" \
            >/dev/null 2>&1 || true
    fi
    if [[ -n $webservice_id ]]; then
        mariadb prestashop --execute \
            "DELETE FROM webservice_permission WHERE id_webservice_account=$webservice_id; DELETE FROM webservice_account_shop WHERE id_webservice_account=$webservice_id; DELETE FROM webservice_account WHERE id_webservice_account=$webservice_id;" \
            >/dev/null 2>&1 || true
    fi
    if [[ $webservice_configured == 1 ]]; then
        if [[ $ws_enabled_exists == 1 ]]; then
            mariadb prestashop --execute \
                "UPDATE configuration SET value='$ws_enabled' WHERE name='PS_WEBSERVICE';" \
                >/dev/null 2>&1 || true
        else
            mariadb prestashop --execute \
                "DELETE FROM configuration WHERE name='PS_WEBSERVICE';" \
                >/dev/null 2>&1 || true
        fi
        clear_app_cache >/dev/null 2>&1 || true
    fi
    rm -f -- "$cookies" "$page" "$headers" "$form_body" \
        "$product_blank" "$product_request" "$product_response" \
        "$product_read" "$adminer_cookies" "$updater_output" \
        "$channel_metadata" "$apt_policy"
}
trap cleanup EXIT

for unit in apache2.service mariadb.service postfix.service multi-user.target; do
    systemctl --quiet is-active "$unit"
done
for unit in apache2.service mariadb.service postfix.service; do
    systemctl --quiet is-enabled "$unit"
done
apache2ctl -t
grep -Fxq 'VERSION_CODENAME=trixie' /etc/os-release
grep -Eq '^turnkey-prestashop-19\.0' /etc/turnkey_version
grep -Fq '[40prestashop] successfully completed' /var/log/inithooks.log

source_manifest=/usr/local/share/turnkey/prestashop-source
grep -Fxq 'version=9.1.5' "$source_manifest"
grep -Fxq 'edition=5.0' "$source_manifest"
grep -Fxq 'archive_sha256=37140cb77c03acf61b832f76893cd8fe1e304b0fc14fa5485cfea4a7bfaf3a72' "$source_manifest"
grep -Fxq 'autoupgrade_version=7.6.5' "$source_manifest"
grep -Fxq 'autoupgrade_sha256=8cbf4b8b615bceef4710bb95708099fc5f2f64671c8196f475c87a76d6f7a2e1' "$source_manifest"

installed_version=$(php -r \
    "require '$webroot/vendor/autoload.php'; echo PrestaShop\\PrestaShop\\Core\\Version::VERSION;")
test "$installed_version" = 9.1.5
php_version=$(php -r 'echo PHP_VERSION;')
[[ $php_version == 8.4.* ]]
autoupgrade_version=$(php -r \
    '$config=simplexml_load_file($argv[1]); echo (string) $config->version;' \
    "$webroot/modules/autoupgrade/config.xml")
test "$autoupgrade_version" = 7.6.5
test "$(db_scalar "SELECT email FROM employee WHERE id_employee=1")" = \
    "$admin_email"
test "$(db_scalar "SELECT value FROM configuration WHERE name='PS_SHOP_DOMAIN' LIMIT 1")" = \
    localhost
test "$(db_scalar "SELECT value FROM configuration WHERE name='PS_SHOP_DOMAIN_SSL' LIMIT 1")" = \
    localhost
php -r '
    require "$argv[1]/vendor/autoload.php";
    $parameters = require "$argv[1]/app/config/parameters.php";
    Defuse\Crypto\Key::loadFromAsciiSafeString(
        $parameters["parameters"]["new_cookie_key"]
    );
' -- "$webroot"

# Prove the public storefront through the configured Apache TLS endpoint.
curl --insecure --fail --silent --show-error --location "$base/" >"$page"
grep -Eqi 'TurnKey PrestaShop|products|shopping cart' "$page"

# Submit the real Symfony administrator login form with its generated hidden
# fields, then require an authenticated back-office page.
curl --insecure --fail --silent --show-error --location \
    --cookie-jar "$cookies" --cookie "$cookies" \
    "$base/administration/" >"$page"
grep -Fq 'id="login_form"' "$page"
admin_login_url=$(TKL_LOGIN_PAGE="$page" TKL_LOGIN_BODY="$form_body" \
    TKL_LOGIN_BASE="$base/administration/" \
    TKL_LOGIN_EMAIL="$admin_email" TKL_LOGIN_PASSWORD="$app_password" \
    python3 - <<'PYTHON'
import os
from html.parser import HTMLParser
from urllib.parse import urlencode, urljoin


class LoginForm(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.active = False
        self.action = None
        self.fields = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "form":
            self.active = attrs.get("id") == "login_form"
            if self.active:
                self.action = attrs.get("action", "")
            return
        if not self.active or tag != "input":
            return
        name = attrs.get("name")
        input_type = attrs.get("type", "text").lower()
        if not name or input_type in {"submit", "button", "password", "email"}:
            return
        if input_type in {"checkbox", "radio"} and "checked" not in attrs:
            return
        self.fields.append((name, attrs.get("value", "")))

    def handle_endtag(self, tag):
        if tag == "form" and self.active:
            self.active = False


with open(os.environ["TKL_LOGIN_PAGE"], encoding="utf-8") as source:
    parser = LoginForm()
    parser.feed(source.read())
if parser.action is None:
    raise RuntimeError("administrator login form action is missing")
parser.fields.extend([
    ("email", os.environ["TKL_LOGIN_EMAIL"]),
    ("passwd", os.environ["TKL_LOGIN_PASSWORD"]),
    ("submit_login", "1"),
    ("stay_logged_in", "1"),
])
with open(os.environ["TKL_LOGIN_BODY"], "w", encoding="utf-8") as destination:
    destination.write(urlencode(parser.fields))
print(urljoin(os.environ["TKL_LOGIN_BASE"], parser.action))
PYTHON
)
curl --insecure --silent --show-error \
    --cookie-jar "$cookies" --cookie "$cookies" \
    --dump-header "$headers" --output "$page" \
    --data-binary "@$form_body" "$admin_login_url"
grep -q '^HTTP/.* 302' "$headers"
curl --insecure --fail --silent --show-error --location \
    --cookie-jar "$cookies" --cookie "$cookies" \
    "$base/administration/" >"$page"
! grep -Fq 'id="login_form"' "$page"
grep -Eqi 'Dashboard|main-menu|logout' "$page"

# Enable a disposable key for PrestaShop's supported Webservice API. The key
# and configuration are removed by the exit trap.
ws_enabled_exists=$(db_scalar "SELECT COUNT(*) FROM configuration WHERE name='PS_WEBSERVICE'")
[[ $ws_enabled_exists =~ ^[01]$ ]]
if [[ $ws_enabled_exists == 1 ]]; then
    ws_enabled=$(db_scalar "SELECT value FROM configuration WHERE name='PS_WEBSERVICE' LIMIT 1")
    test -n "$ws_enabled"
fi
api_key=$(printf '%032d' "$$")
webservice_configured=1
if [[ $ws_enabled_exists == 1 ]]; then
    mariadb prestashop --execute \
        "UPDATE configuration SET value='1' WHERE name='PS_WEBSERVICE';"
else
    mariadb prestashop --execute \
        "INSERT INTO configuration (id_shop_group,id_shop,name,value,date_add,date_upd) VALUES (NULL,NULL,'PS_WEBSERVICE','1',NOW(),NOW());"
fi
webservice_id=$(mariadb --batch --skip-column-names prestashop --execute \
    "INSERT INTO webservice_account (\`key\`, description, class_name, is_module, active) VALUES ('$api_key', 'TurnKey v19 disposable acceptance', 'WebserviceRequest', 0, 1); SELECT LAST_INSERT_ID();" | tail -n1)
[[ $webservice_id =~ ^[1-9][0-9]*$ ]]
mariadb prestashop --execute \
    "INSERT INTO webservice_account_shop (id_webservice_account,id_shop) VALUES ($webservice_id,1); INSERT INTO webservice_permission (resource,method,id_webservice_account) VALUES ('products','GET',$webservice_id),('products','POST',$webservice_id),('products','DELETE',$webservice_id);"
clear_app_cache

curl --insecure --fail --silent --show-error --user "$api_key:" \
    "$base/api/products?schema=blank" >"$product_blank"
marker="TurnKey v19 acceptance product $$"
TKL_PRODUCT_INPUT="$product_blank" TKL_PRODUCT_OUTPUT="$product_request" \
    TKL_PRODUCT_NAME="$marker" python3 - <<'PYTHON'
import os
import xml.etree.ElementTree as ET


tree = ET.parse(os.environ["TKL_PRODUCT_INPUT"])
product = tree.getroot().find("product")
if product is None:
    raise RuntimeError("blank product schema is missing")


def set_value(name, value, required=True):
    node = product.find(name)
    if node is None:
        if required:
            raise RuntimeError(f"blank product schema has no {name}")
        return
    node.text = value


values = {
    "id_manufacturer": "1",
    "id_supplier": "1",
    "id_category_default": "2",
    "new": "1",
    "id_tax_rules_group": "1",
    "type": "1",
    "id_shop_default": "1",
    "reference": "TKL-V19",
    "state": "1",
    "product_type": "standard",
    "price": "19.00",
    "unit_price": "19.00",
    "active": "1",
}
for field, value in values.items():
    set_value(field, value, required=field != "type")

localized = {
    "name": os.environ["TKL_PRODUCT_NAME"],
    "link_rewrite": "turnkey-v19-acceptance-product",
    "description_short": "TurnKey PrestaShop v19 product round trip",
    "description": "TurnKey PrestaShop v19 product round trip",
    "meta_description": "TurnKey PrestaShop v19 product round trip",
    "meta_keywords": "turnkey prestashop",
    "meta_title": os.environ["TKL_PRODUCT_NAME"],
}
for field, value in localized.items():
    node = product.find(field)
    if node is None:
        if field == "meta_keywords":
            continue
        raise RuntimeError(f"blank product schema has no {field}")
    languages = node.findall("language")
    if not languages:
        raise RuntimeError(f"blank product schema has no language for {field}")
    for language in languages:
        language.text = value

categories = product.find("associations/categories")
if categories is not None:
    category_nodes = categories.findall("category")
    if category_nodes:
        for extra in category_nodes[1:]:
            categories.remove(extra)
        category_id = category_nodes[0].find("id")
        if category_id is not None:
            category_id.text = "2"
associations = product.find("associations")
if associations is not None:
    for association in list(associations):
        if association.tag != "categories":
            associations.remove(association)

allowed = set(values) | set(localized) | {"associations"}
for field in list(product):
    if field.tag not in allowed:
        product.remove(field)

tree.write(os.environ["TKL_PRODUCT_OUTPUT"], encoding="utf-8", xml_declaration=True)
PYTHON

product_status=$(curl --insecure --silent --show-error --user "$api_key:" \
    --header 'Content-Type: application/xml' \
    --data-binary "@$product_request" --output "$product_response" \
    --write-out '%{http_code}' "$base/api/products")
if [[ ! $product_status =~ ^2[0-9][0-9]$ ]]; then
    printf 'product_create_http_status=%s\n' "$product_status" >&2
    sed -n '1,80p' "$product_response" >&2
    false
fi
product_id=$(python3 - "$product_response" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET

value = ET.parse(sys.argv[1]).getroot().findtext(".//product/id", "")
if not value.isdigit() or int(value) < 1:
    raise RuntimeError("created product response has no numeric id")
print(value)
PYTHON
)

curl --insecure --fail --silent --show-error --user "$api_key:" \
    "$base/api/products/$product_id" >"$product_read"
grep -Fq "$marker" "$product_read"
test "$(db_scalar "SELECT name FROM product_lang WHERE id_product=$product_id AND id_lang=1 AND id_shop=1")" = \
    "$marker"
curl --insecure --fail --silent --show-error --location \
    "$base/index.php?id_product=$product_id&controller=product" >"$page"
grep -Fq "$marker" "$page"

curl --insecure --fail --silent --show-error --user "$api_key:" \
    --request DELETE "$base/api/products/$product_id" >/dev/null
test "$(db_scalar "SELECT COUNT(*) FROM product WHERE id_product=$product_id")" = 0
product_id=

# Verify the LAMP administration claims exposed by this appliance.
test "$(postconf -h inet_interfaces)" = localhost
ss -ltn | awk '$4 ~ /^(127\.0\.0\.1|\[::1\]):25$/ { found=1 } END { exit !found }'
dpkg-query -W adminer webmin-apache webmin-mysql webmin-phpini postfix \
    apache2 mariadb-server >/dev/null
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null
curl --insecure --fail --silent --show-error \
    https://127.0.0.1:12322/ >"$page"
grep -qi Adminer "$page"
curl --insecure --silent --show-error --location \
    --cookie-jar "$adminer_cookies" --cookie "$adminer_cookies" \
    --data-urlencode 'auth[driver]=server' \
    --data-urlencode 'auth[server]=localhost' \
    --data-urlencode 'auth[username]=adminer' \
    --data-urlencode "auth[password]=$db_password" \
    --data-urlencode 'auth[db]=prestashop' \
    https://127.0.0.1:12322/ >"$page"
grep -qi prestashop "$page"
grep -qi Logout "$page"

# Run the supported Update Assistant discovery command without applying a
# release, then corroborate the stable channel with official release metadata.
before_version=$(php -r \
    "require '$webroot/vendor/autoload.php'; echo PrestaShop\\PrestaShop\\Core\\Version::VERSION;")
su -p -s /bin/sh -c \
    'php /var/www/prestashop/modules/autoupgrade/bin/console update:check-new-version administration --no-ansi' \
    www-data >"$updater_output"
grep -Fq 'Version' "$updater_output"
grep -Fq 'Channel' "$updater_output"
test "$(php -r \
    "require '$webroot/vendor/autoload.php'; echo PrestaShop\\PrestaShop\\Core\\Version::VERSION;")" = \
    "$before_version"

curl --fail --silent --show-error \
    https://assets.prestashop3.com/dst/edition/corporate/edition_versions.js \
    >"$channel_metadata"
stable_edition=$(python3 - "$channel_metadata" <<'PYTHON'
import re
import sys

metadata = open(sys.argv[1], encoding="utf-8").read()
versions = re.findall(r'"version"\s*:\s*"([^"]+)"', metadata)
stable = next((version for version in versions if not re.search(r'alpha|beta|rc', version, re.I)), "")
if not stable:
    raise RuntimeError("official stable channel is empty")
print(stable)
PYTHON
)
[[ $stable_edition == 9.1.5-* ]]

apache_version=$(dpkg-query -W -f='${Version}' apache2)
mariadb_version=$(dpkg-query -W -f='${Version}' mariadb-server)
adminer_version=$(dpkg-query -W -f='${Version}' adminer)
before_packages="$apache_version|$mariadb_version|$adminer_version"
apt-get update >/dev/null
for package in apache2 mariadb-server php adminer; do
    apt-cache policy "$package" >"$apt_policy"
    candidate_version=$(awk '/Candidate:/ {print $2}' "$apt_policy")
    test -n "$candidate_version"
    test "$candidate_version" != '(none)'
    grep -Eq 'trixie|deb13' "$apt_policy"
done
after_packages="$(dpkg-query -W -f='${Version}' apache2)|$(dpkg-query -W -f='${Version}' mariadb-server)|$(dpkg-query -W -f='${Version}' adminer)"
test "$after_packages" = "$before_packages"
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -Rqi bookworm /etc/apt/sources.list.d

cat >"$result" <<EOF
package_source=Official PrestaShop $installed_version Classic production archive and official Update Assistant $autoupgrade_version release; PHP, MariaDB, Apache, Postfix and Adminer from Debian Trixie
installed_version=PrestaShop $installed_version; Update Assistant $autoupgrade_version; PHP $php_version; apache2 $apache_version; mariadb-server $mariadb_version; adminer $adminer_version
runtime_checks=normal init and firstboot; Apache HTTPS storefront; real administrator login; Webservice product create and read with direct MariaDB and storefront readback; product deletion; loopback Postfix; authenticated Adminer database view; Webmin endpoint
updater_command=Update Assistant update:check-new-version administration; official edition_versions.js stable-channel query; apt-get update with apt-cache policy
updater_result=Update Assistant discovery exited successfully with installed PrestaShop unchanged; official stable metadata reported $stable_edition; signed Trixie metadata refreshed with installed packages unchanged
updater_channel=PrestaShop Update Assistant online and online_recommended channels; official PrestaShop Classic stable feed; Debian and TurnKey Trixie APT repositories
integrity_evidence=build verifies pinned SHA-256 for the official PrestaShop and Update Assistant archives; the Update Assistant digest matches the official GitHub asset digest; APT accepted signed Trixie metadata; no Bookworm source remained
EOF
