COMMON_CONF = apache-credit
CREDIT_LOCATION = ~ "^/(?!(administration))"

include $(FAB_PATH)/common/mk/turnkey/lamp.mk
include $(FAB_PATH)/common/mk/turnkey.mk
