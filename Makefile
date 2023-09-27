COMMON_CONF = apache-credit
CREDIT_LOCATION = ~ "^/(?!(administration))"

PHP_VERSION=8.1
PHP_MEMORY_LIMIT = 256M
PHP_POST_MAX_SIZE = 128M
PHP_UPLOAD_MAX_FILESIZE = 128M

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey.mk
