LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

APP_PLATFORM := android-13

LOCAL_MODULE := LuaScriptCore-Unity-Android
LOCAL_LDFLAGS := -Wl,--build-id
LOCAL_LDLIBS := \
	-llog \

LOCAL_SRC_FILES := \
    $(LOCAL_PATH)/../../../../../UnityCommon/LuaScriptCoreForUnity.cpp \
    $(LOCAL_PATH)/../../../../../UnityCommon/LuaUnityEnv.cpp \
    $(LOCAL_PATH)/../../../../../UnityCommon/LuaUnityExportTypeDescriptor.cpp \
    $(LOCAL_PATH)/../../../../../UnityCommon/LuaUnityExportMethodDescriptor.cpp \
    $(LOCAL_PATH)/../../../../../UnityCommon/LuaUnityExportPropertyDescriptor.cpp \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lapi.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lauxlib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lbaselib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lbitlib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lcode.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lcorolib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lctype.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ldblib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ldebug.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ldo.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ldump.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lfunc.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lgc.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/linit.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/liolib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/llex.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lmathlib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lmem.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/loadlib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lobject.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lopcodes.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/loslib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lparser.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lstate.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lstring.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lstrlib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ltable.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ltablib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/ltm.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lua.hpp \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lundump.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lunity.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lutf8lib.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lvm.c \
	$(LOCAL_PATH)/../../../../../../lua-core/src/lzio.c \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaContext.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaFunction.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaNativeClass.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaNativeClassFactory.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaObject.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaObjectDecoder.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaObjectDescriptor.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaObjectEncoder.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaObjectManager.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaPointer.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaValue.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaTuple.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/StringUtils.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaDataExchanger.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaManagedObject.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaSession.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaEngineAdapter.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaExportTypeDescriptor.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaExportMethodDescriptor.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaExportsTypeManager.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaExportPropertyDescriptor.cpp \
	$(LOCAL_PATH)/../../../../../../lua-common/LuaTmpValue.cpp \

LOCAL_C_INCLUDES += $(LOCAL_PATH)
LOCAL_C_INCLUDES += $(LOCAL_PATH)/../../../../../../lua-core/src
LOCAL_C_INCLUDES += $(LOCAL_PATH)/../../../../../../lua-common
LOCAL_C_INCLUDES += $(LOCAL_PATH)/../../../../../UnityCommon

include $(BUILD_SHARED_LIBRARY)
