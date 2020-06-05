COMMON_CONF = apache-credit
CREDIT_LOCATION = ~ "^/(?!(administration))"

PHP_MEMORY_LIMIT = 256
PHP_POST_MAX_SIZE = 128
PHP_UPLOAD_MAX_FILESIZE = 128

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey.mk
