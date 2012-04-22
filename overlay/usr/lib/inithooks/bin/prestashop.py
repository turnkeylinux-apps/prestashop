#!/usr/bin/python
"""Set PrestaShop admin password and email

Option:
    --pass=     unless provided, will ask interactively
    --email=    unless provided, will ask interactively

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

def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], "h",
                                       ['help', 'pass=', 'email='])
    except getopt.GetoptError, e:
        usage(e)

    password = ""
    email = ""
    for opt, val in opts:
        if opt in ('-h', '--help'):
            usage()
        elif opt == '--pass':
            password = val
        elif opt == '--email':
            email = val

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
            min_length=5)

    for line in file('/var/www/prestashop/config/settings.inc.php').readlines():
        m = re.match("define\('_COOKIE_KEY_', '(.*)'", line.strip())
        if m:
            cookie_key = m.group(1)

    hashpass = hashlib.md5(cookie_key + password).hexdigest()

    m = MySQL()
    m.execute('UPDATE prestashop.employee SET email=\"%s\" WHERE id_employee=\"1\";' % email)
    m.execute('UPDATE prestashop.employee SET passwd=\"%s\" WHERE id_employee=\"1\";' % hashpass)

if __name__ == "__main__":
    main()

