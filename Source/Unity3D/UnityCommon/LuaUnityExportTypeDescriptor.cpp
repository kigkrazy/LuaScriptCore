//
//  LuaUnityExportTypeDescriptor.cpp
//  LuaScriptCore
//
//  Created by 冯鸿杰 on 2017/9/27.
//  Copyright © 2017年 冯鸿杰. All rights reserved.
//

#include "LuaUnityExportTypeDescriptor.hpp"
#include "LuaUnityEnv.hpp"
#include "LuaObjectDescriptor.h"

LuaUnityExportTypeDescriptor::LuaUnityExportTypeDescriptor(std::string name, LuaExportTypeDescriptor *parentTypeDescriptor) : LuaExportTypeDescriptor(name, parentTypeDescriptor)
{
    
}

LuaExportTypeDescriptor* LuaUnityExportTypeDescriptor::createSubType(LuaSession *session, std::string subTypeName)
{
    LuaUnityExportTypeDescriptor *subTypeDescriptor = new LuaUnityExportTypeDescriptor(subTypeName, this);
    
    subTypeDescriptor -> createInstanceHandler = createInstanceHandler;
    subTypeDescriptor -> destroyInstanceHandler = destroyInstanceHandler;
    subTypeDescriptor -> instanceDescriptionHandler = instanceDescriptionHandler;
    
    return subTypeDescriptor;
}

LuaObjectDescriptor* LuaUnityExportTypeDescriptor::createInstance(LuaSession *session)
{
    LuaObjectDescriptor *objectDescriptor = NULL;
    
    if (createInstanceHandler != NULL)
    {
        long long instanceId = createInstanceHandler(objectId());
        objectDescriptor = new LuaObjectDescriptor((void *)instanceId, this);
        
        //设置本地对象标识
        LuaUnityEnv::sharedInstance() -> setNativeObjectId(objectDescriptor -> getObject(),
                                                           objectDescriptor -> objectId(),
                                                           objectDescriptor -> getLinkId());
    }
    
    return objectDescriptor;
}

void LuaUnityExportTypeDescriptor::destroyInstance(LuaSession *session, LuaObjectDescriptor *objectDescriptor)
{
    if (destroyInstanceHandler != NULL)
    {
        destroyInstanceHandler((long long)objectDescriptor -> getObject());
    }
}
