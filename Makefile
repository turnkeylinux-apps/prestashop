COMMON_CONF = apache-credit
CREDIT_LOCATION = ~ "^/(?!(administration))"

PHP_MEMORY_LIMIT = 256

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey.mk
