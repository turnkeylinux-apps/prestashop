PrestaShop - Easy to use online shop
====================================

`PrestaShop`_ is a popular, easy to use e-commerce solution for small to
medium-sized online shops. Features include support for 38 languages,
special deals and promotions, cross-selling, affiliate programs. The
open source edition supports payment gateways such as Google checkout,
and PayPal with further payment modules offered commercially.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Prestashop configurations:
   
   - Installed from upstream source code to /var/www/prestashop
   - Administration link set to: https://$your_domain/administration
   - Optimized SEO URL's enabled by default.

-  SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
-  Postfix MTA (bound to localhost) to allow sending of email from
   web applications (e.g., password recovery)
-  Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL, phpMyAdmin: username **root**


.. _PrestaShop: http://www.prestashop.com/
.. _TurnKey Core: http://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
