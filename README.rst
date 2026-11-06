PrestaShop - Easy to use online shop
====================================

`PrestaShop`_ is an open source e-commerce application for managing products,
customers and orders. Configure payment and shipping options in the back office,
with additional integrations supplied by modules.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Prestashop configurations:
   
   - Installed from upstream source code to /var/www/prestashop
   - Administration link set to: https://$your_domain/administration
   - Optimized SEO URL's enabled by default.

   **Security note**: PrestaShop updates require supervision. The included
   Update Assistant checks the supported online channel and can perform an
   update after the administrator takes a backup. See `PrestaShop update
   documentation`_ for the supported web and command-line workflows.

-  SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
-  Postfix MTA (bound to localhost) to allow sending of email from
   web applications (e.g., password recovery)
-  Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Before accepting orders, configure your store identity and contact details,
shipping, taxes, payment methods and the Customer Reassurance policies. Choose
your timezone under **International > Localization**. On older v19 images,
replace the default **US/Eastern** with **America/New_York** (or your local
canonical timezone) so PHP can use it correctly.

Updating the store
------------------

Back up the shop files and database before updating. Update the Update Assistant
module first; version 7.6.6 or newer is required for PrestaShop 9.2. If Module
Manager does not offer it, upload the official `Update Assistant releases`_ ZIP
through **Modules > Module Manager > Upload a module**. In the back office, open
**Shop Parameters > General > Maintenance**, set **Enable store** to **No**,
click **Add my IP**, and **Save**. Update Assistant requires the maintenance IP
even when the store allows access for logged-in employees. Open Update Assistant
and complete its requirements check, backup and update steps. Verify the store
and enable it again after the update succeeds.

If product images are missing after changing the shop domain, refresh generated
URLs from the server console::

    runuser -u www-data -- turnkey-prestashop-refresh-urls

This also repairs malformed default Customer Reassurance icon URLs and preserves
customized icons. The firstboot setup runs it automatically.

For Prestashop news and updates, including security updates, we
recommend that you subscribe to the `Prestashop Blog`_.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  PrestaShop: username is email set on first boot

.. _PrestaShop: https://www.prestashop.com/
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _PrestaShop update documentation: https://devdocs.prestashop-project.org/9/basics/keeping-up-to-date/
.. _Adminer: https://www.adminer.org/
.. _Prestashop Blog: https://www.prestashop.com/en/blog

.. _Update Assistant releases: https://github.com/PrestaShop/autoupgrade/releases
