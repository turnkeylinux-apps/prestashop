#!/usr/bin/python
"""Set PrestaShop admin password, email and domain to serve

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively
    --domain=   unless provided, will ask interactively
                DEFAULT=www.example.com

"""
import re
import sys
import getopt
import hashlib

from dialog_wrapper import Dialog
from mysqlconf import MySQL

def usage(s=None):
    if s:
        print >> sys.stderr, "Error:", s
    print >> sys.stderr, "Syntax: %s [options]" % sys.argv[0]
    print >> sys.stderr, __doc__
    sys.exit(1)

DEFAULT_DOMAIN="www.example.com"

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email=', 'domain='])
    except getopt.GetoptError, e:
        usage(e)

    email = ""
    domain = ""
    password = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val
        elif opt == '--domain':
            domain = val

    if not email:
        d = Dialog('TurnKey Linux - First boot configuration')
        email = d.get_email(
            "PrestaShop Email",
            "Enter email address for the PrestaShop 'admin' account.",
            "admin@example.com")

    if not password:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        password = d.get_password(
            "PrestaShop Password",
            "Enter new password for the PrestaShop '%s' account." % email,
            pass_req=8)

    if not domain:
        if 'd' not in locals():
            d = Dialog('TurnKey Linux - First boot configuration')

        domain = d.get_input(
            "PrestaShop Domain",
            "Enter the domain to serve Prestashop.",
            DEFAULT_DOMAIN)

    if domain == "DEFAULT":
        domain = DEFAULT_DOMAIN

    for line in file('/var/www/prestashop/config/settings.inc.php').readlines():
        m = re.match("define\('_COOKIE_KEY_', '(.*)'", line.strip())
        if m:
            cookie_key = m.group(1)

    hashpass = hashlib.md5(cookie_key + password).hexdigest()

    m = MySQL()
    m.execute('UPDATE prestashop.ps_employee SET email=\"%s\" WHERE id_employee=\"1\";' % email)
    m.execute('UPDATE prestashop.ps_employee SET passwd=\"%s\" WHERE id_employee=\"1\";' % hashpass)
    m.execute('UPDATE prestashop.ps_configuration SET value=\"%s\" WHERE name=\"PS_SHOP_DOMAIN\";' % domain)
    m.execute('UPDATE prestashop.ps_configuration SET value=\"%s\" WHERE name=\"PS_SHOP_DOMAIN_SSL\";' % domain)
    m.execute('UPDATE prestashop.ps_shop_url SET domain=\"%s\" WHERE id_shop_url=\"1\";' % domain)
    m.execute('UPDATE prestashop.ps_shop_url SET domain_ssl=\"%s\" WHERE id_shop_url=\"1\";' % domain)



if __name__ == "__main__":
    main()

