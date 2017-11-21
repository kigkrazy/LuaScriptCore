//
// Created by 冯鸿杰 on 16/9/28.
//

#ifndef ANDROID_LUAJAVATYPE_H
#define ANDROID_LUAJAVATYPE_H

#include <string>
#include "jni.h"

/**
 * Java类型
 */
class LuaJavaType
{
public:

    /**
     * 获取Field类
     *
     * @param env JNI环境
     *
     * @return Field类型
     */
    static jclass fieldClass(JNIEnv *env);

    /**
     * 获取Method类
     *
     * @param env JNI环境
     *
     * @return Method类型
     */
    static jclass methodClass(JNIEnv *env);

    /**
     * 获取LuaContext类
     *
     * @param env JNI环境
     *
     * @erturn LuaContext类型
     */
    static jclass contextClass(JNIEnv *env);

    /**
     * 获取LuaModule类
     *
     * @param env JNI环境
     *
     * @return LuaModule类型
     */
    static jclass moduleClass(JNIEnv *env);

    /**
     * 获取LuaValue类
     *
     * @param env JNI环境
     *
     * @return LuaValue类型
     */
    static jclass luaValueClass(JNIEnv *env);

    /**
     * 获取LuaValueType类
     *
     * @param env JNI环境
     *
     * @return LuaValueType类型
     */
    static jclass luaValueTypeClass(JNIEnv *env);

    /**
     * 获取String类
     *
     * @param env JNI环境
     *
     * @return String类型
     */
    static jclass stringClass(JNIEnv *env);

    /**
     * 获取Short类型
     *
     * @param env JNI环境
     *
     * @return Short类型
     */
    static jclass shortClass(JNIEnv *env);

    /**
     * 获取Integer类
     *
     * @param env JNI环境
     *
     * @return Integer类型
     */
    static jclass integerClass(JNIEnv *env);

    /**
     * 获取Double类
     *
     * @param env JNI环境
     *
     * @return Double类型
     */
    static jclass doubleClass(JNIEnv *env);

    /**
     * 获取Float类型
     *
     * @param env JNI环境
     *
     * @return Float类型
     */
    static jclass floatClass(JNIEnv *env);

    /**
     * 获取Long类型
     *
     * @param env JNI环境
     *
     * @return Long类型
     */
    static jclass longClass(JNIEnv *env);

    /**
     * 获取Boolean类
     *
     * @param env JNI环境
     *
     * @return Boolean类型
     */
    static jclass booleanClass(JNIEnv *env);

    /**
     * 获取Byte类
     *
     * @param env JNI环境
     *
     * @return Byte类型
     */
    static jclass byteClass(JNIEnv *env);

    /**
     * 获取byte[]类
     *
     * @param env JNI环境
     *
     * @return byte[]类型
     */
    static jclass bytesClass(JNIEnv *env);

    /**
     * 获取Byte[]类
     *
     * @param env JNI环境
     *
     * @return Byte[]类型
     */
    static jclass byteArrayClass(JNIEnv *env);

    /**
     * 获取ArrayList类
     *
     * @param env JNI环境
     *
     * @return ArrayList类型
     */
    static jclass arrayListClass(JNIEnv *env);

    /**
     * 获取HashMap类
     *
     * @param env JNI环境
     *
     * @return HashMap类型
     */
    static jclass hashMapClass(JNIEnv *env);

    /**
     * 获取LuaBaseObject类型
     *
     * @param env JNI环境
     *
     * @return LuaBaseObject类型
     */
    static jclass luaBaseObjectClass(JNIEnv *env);

    /**
     * 获取LuaObjectClass类
     *
     * @param env JNI环境
     *
     * @return LuaObjectClass类型
     */
    static jclass luaObjectClass(JNIEnv *env);

    /**
     * 获取LuaPointer类
     *
     * @param env JNI环境
     *
     * @return LuaPoiter类型
     */
    static jclass pointerClass(JNIEnv *env);

    /**
     * 获取LuaFunction类
     *
     * @param env JNI环境
     *
     * @return LuaFunction类型
     */
    static jclass functionClass(JNIEnv *env);

    /**
     * 获取LuaTuple类
     *
     * @param env JNI环境
     *
     * @return LuaTuple类型
     */
    static jclass tupleClass(JNIEnv *env);

    /**
     * 获取LuaExportTypeManager类型
     *
     * @param env JNI环境
     *
     * @return LuaExportTypeManager类型
     */
    static jclass exportTypeManagerClass(JNIEnv *env);

    /**
     * 获取LuaExportType类型
     *
     * @param env JNI环境
     *
     * @return LuaExportType类型
     */
    static jclass luaExportTypeClass(JNIEnv *env);
};


#endif //ANDROID_LUAJAVATYPE_H
