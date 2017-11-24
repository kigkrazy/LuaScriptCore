//
//  LSCModuleExporter.m
//  LuaScriptCore
//
//  Created by 冯鸿杰 on 2017/9/5.
//  Copyright © 2017年 vimfung. All rights reserved.
//

#import "LSCExportsTypeManager.h"
#import "LSCContext_Private.h"
#import "LSCSession_Private.h"
#import "LSCEngineAdapter.h"
#import "LSCValue.h"
#import "LSCPointer.h"
#import "LSCExportTypeDescriptor.h"
#import "LSCExportMethodDescriptor.h"
#import "LSCExportTypeAnnotation.h"
#import <objc/runtime.h>

@interface LSCExportsTypeManager ()

/**
 上下文对象
 */
@property (nonatomic, weak) LSCContext *context;

/**
 导出类型描述集合
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *, LSCExportTypeDescriptor *> *exportTypes;

/**
 导出类型映射表
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *exportTypesMapping;

/**
 方法映射表
 */
@property (nonatomic, strong) NSMutableDictionary<NSString *,LSCExportMethodDescriptor *> *methodsMapping;

@end

@implementation LSCExportsTypeManager

- (instancetype)initWithContext:(LSCContext *)context
{
    if (self = [super init])
    {
        self.context = context;
        
        //检测接口
        self.exportTypes = [NSMutableDictionary dictionary];
        self.exportTypesMapping = [NSMutableDictionary dictionary];
        self.methodsMapping = [NSMutableDictionary dictionary];
        [self _setupExportsTypes];
        
        //设置环境
        [self _setupExportEnv];
    }
    
    return self;
}

- (BOOL)checkExportsTypeWithObject:(id)object
{
    LSCExportTypeDescriptor *typeDescriptor = [self _typeDescriptorWithObject:object];
    if (typeDescriptor)
    {
        return YES;
    }
    
    return NO;
}

- (void)createLuaObjectByObject:(id)object
{
    LSCExportTypeDescriptor *typeDescriptor = [self _typeDescriptorWithObject:object];
    if (typeDescriptor)
    {
        lua_State *state = self.context.currentSession.state;
        [LSCEngineAdapter getGlobal:state name:typeDescriptor.typeName.UTF8String];
        [LSCEngineAdapter pop:state count:1];
        
        [self _initLuaObjectWithObject:object type:typeDescriptor];
    }
}

#pragma mark - Private

/**
 设置导出环境
 */
- (void)_setupExportEnv
{
    //为_G设置元表，用于监听其对象的获取，从而找出哪些是导出类型
    lua_State *state = self.context.currentSession.state;
    [LSCEngineAdapter getGlobal:state name:"_G"];
    
    if (![LSCEngineAdapter isTable:state index:-1])
    {
        [self.context raiseExceptionWithMessage:@"Invalid '_G' object，setup the exporter fail."];
        [LSCEngineAdapter pop:state count:1];
        return;
    }
    
    //创建_G元表
    [LSCEngineAdapter newTable:state];
    
    //监听__index元方法
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushCClosure:globalIndexMetaMethodHandler n:1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__index"];
    
    //绑定为_G元表
    [LSCEngineAdapter setMetatable:state index:-2];
    
    [LSCEngineAdapter pop:state count:1];
}

/**
 初始化导出类型
 */
- (void)_setupExportsTypes
{
    //注册基类Object
    LSCExportTypeDescriptor *objectTypeDescriptor = [LSCExportTypeDescriptor objectTypeDescriptor];
    [self.exportTypes setObject:objectTypeDescriptor forKey:objectTypeDescriptor.typeName];
    
    //反射所有类型,并找出所有导出类型
    uint numClasses;
    
    Class *classList = objc_copyClassList(&numClasses);
    
    for (int i = 0; i < numClasses; i++)
    {
        Class cls = *(classList + i);
        
        if (class_getClassMethod(cls, @selector(conformsToProtocol:))
            && [cls conformsToProtocol:@protocol(LSCExportType)])
        {
            LSCExportTypeDescriptor *typeDescriptor = [[LSCExportTypeDescriptor alloc] initWithTypeName:[self _typeNameWithClass:cls]
                                                                                             nativeType:cls];

            [self.exportTypes setObject:typeDescriptor
                                 forKey:typeDescriptor.typeName];
            [self.exportTypesMapping setObject:typeDescriptor.typeName
                                        forKey:NSStringFromClass(cls)];
        }
    }
    
    free(classList);
}

/**
 准备导出类型到Lua中

 @param typeDescriptor 类型描述
 */
- (void)_prepareExportsTypeWithDescriptor:(LSCExportTypeDescriptor *)typeDescriptor
{
    lua_State *state = self.context.mainSession.state;

    //判断父类是否为导出类型
    LSCExportTypeDescriptor *parentTypeDescriptor = [self _findParentTypeDescriptorWithTypeDescriptor:typeDescriptor];
    if (parentTypeDescriptor)
    {
        //导入父级类型
        [LSCEngineAdapter getGlobal:state name:parentTypeDescriptor.typeName.UTF8String];
        [LSCEngineAdapter pop:state count:1];
    }
    
    [self _exportsType:typeDescriptor state:state];
}

/**
 导出类型

 @param typeDescriptor 类型描述
 @param state Lua状态
 */
- (void)_exportsType:(LSCExportTypeDescriptor *)typeDescriptor state:(lua_State *)state
{
    //创建类模块
    [LSCEngineAdapter newTable:state];
    
    //设置类名, since ver 1.3
    [LSCEngineAdapter pushString:typeDescriptor.typeName.UTF8String state:state];
    [LSCEngineAdapter setField:state index:-2 name:"name"];
    
    //关联本地类型
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)(typeDescriptor) state:state];
    [LSCEngineAdapter setField:state index:-2 name:"_nativeType"];

    /**
     fixed : 由于OC中类方法存在继承关系，因此，直接导出某个类定义的类方法无法满足这种继承关系。
     例如：moduleName方法在Object中定义，但是当其子类调用时由于只能取到当前导出方法的类型(Object)，无法取到调用方法的类型(即Object的子类)，因此导致逻辑处理的异常。
     所以，该处改为导出其继承的所有类方法来满足该功能需要。
     **/
    //导出声明的类方法
    [self _exportsClassMethods:typeDescriptor state:state];

    //添加创建对象方法
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
    [LSCEngineAdapter pushCClosure:objectCreateHandler n:2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"create"];

    //添加子类化对象方法
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
    [LSCEngineAdapter pushCClosure:subClassHandler n:2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"subclass"];

    //增加子类判断方法, since ver 1.3
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
    [LSCEngineAdapter pushCClosure:subclassOfHandler n:2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"subclassOf"];
    
    //关联索引
    [LSCEngineAdapter pushValue:-1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__index"];
    
    //类型描述
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
    [LSCEngineAdapter pushCClosure:classToStringHandler n:2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__tostring"];
    
    //获取父类型
    LSCExportTypeDescriptor *parentTypeDescriptor = typeDescriptor.parentTypeDescriptor;

    //关联父类模块
    if (parentTypeDescriptor)
    {
        //存在父类，则直接设置父类为元表
        [LSCEngineAdapter getGlobal:state name:parentTypeDescriptor.typeName.UTF8String];
        if ([LSCEngineAdapter isTable:state index:-1])
        {
            //设置父类指向
            [LSCEngineAdapter pushValue:-1 state:state];
            [LSCEngineAdapter setField:state index:-3 name:"super"];
            
            //关联元表
            [LSCEngineAdapter setMetatable:state index:-2];
        }
        else
        {
            [LSCEngineAdapter pop:state count:1];
        }
    }
    else
    {
        //Object需要创建一个新table来作为元表，否则无法使用元方法，如：print(Object);
        [LSCEngineAdapter newTable:state];
        
        //类型描述
        [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
        [LSCEngineAdapter pushCClosure:classToStringHandler n:1 state:state];
        [LSCEngineAdapter setField:state index:-2 name:"__tostring"];

        [LSCEngineAdapter setMetatable:state index:-2];
    }

    [LSCEngineAdapter setGlobal:state name:typeDescriptor.typeName.UTF8String];

    //---------创建实例对象原型表---------------
    [LSCEngineAdapter newMetatable:state name:typeDescriptor.prototypeTypeName.UTF8String];

    [LSCEngineAdapter getGlobal:state name:typeDescriptor.typeName.UTF8String];
    [LSCEngineAdapter setField:state index:-2 name:"class"];

    [LSCEngineAdapter pushLightUserdata:(__bridge void *)(typeDescriptor) state:state];
    [LSCEngineAdapter setField:state index:-2 name:"_nativeType"];

    [LSCEngineAdapter pushValue:-1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__index"];

    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushCClosure:objectDestroyHandler n:1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__gc"];

    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
    [LSCEngineAdapter pushCClosure:prototypeToStringHandler n:2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__tostring"];

    //给类元表绑定该实例元表
    [LSCEngineAdapter getGlobal:state name:typeDescriptor.typeName.UTF8String];
    [LSCEngineAdapter pushValue:-2 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"prototype"];
    [LSCEngineAdapter pop:state count:1];

    //导出实例方法
    [self _exportsInstanceMethods:typeDescriptor state:state];

    if (parentTypeDescriptor)
    {
        //关联父类
        [LSCEngineAdapter getMetatable:state name:parentTypeDescriptor.prototypeTypeName.UTF8String];
        if ([LSCEngineAdapter isTable:state index:-1])
        {
            //设置父类访问属性 since ver 1.3
            [LSCEngineAdapter pushValue:-1 state:state];
            [LSCEngineAdapter setField:state index:-3 name:"super"];
            
            //设置父类元表
            [LSCEngineAdapter setMetatable:state index:-2];
        }
        else
        {
            [LSCEngineAdapter pop:state count:1];
        }
        
    }
    else
    {
        //Object需要创建一个新table来作为元表，否则无法使用元方法，如：print(Object);
        [LSCEngineAdapter newTable:state];
        
        [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
        [LSCEngineAdapter pushCClosure:objectDestroyHandler n:1 state:state];
        [LSCEngineAdapter setField:state index:-2 name:"__gc"];
        
        [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
        [LSCEngineAdapter pushCClosure:prototypeToStringHandler n:1 state:state];
        [LSCEngineAdapter setField:state index:-2 name:"__tostring"];
        
        [LSCEngineAdapter setMetatable:state index:-2];
        
        //Object类需要增加一些特殊方法
        //创建instanceOf方法 since ver 1.3
        [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
        [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
        [LSCEngineAdapter pushCClosure:instanceOfHandler n:2 state:state];
        [LSCEngineAdapter setField:state index:-2 name:"instanceOf"];
    }
    
    [LSCEngineAdapter pop:state count:1];
}

- (void)_exportsClassMethods:(LSCExportTypeDescriptor *)typeDescriptor
                  targetType:(LSCExportTypeDescriptor *)targetTypeDescriptor
                       state:(lua_State *)state
{
    if (targetTypeDescriptor.nativeType != NULL)
    {
        NSArray *excludesMethodNames = nil;
        Class metaType = objc_getMetaClass(NSStringFromClass(targetTypeDescriptor.nativeType).UTF8String);
        
        //先判断是否有实现注解的排除类方法
        if (class_conformsToProtocol(targetTypeDescriptor.nativeType, @protocol(LSCExportTypeAnnotation)))
        {
            if (class_respondsToSelector(targetTypeDescriptor.nativeType, @selector(excludeExportClassMethods)))
            {
                excludesMethodNames = [targetTypeDescriptor.nativeType excludeExportClassMethods];
            }
        }
        
        //解析方法
        NSMutableDictionary *methodDict = [typeDescriptor.classMethods mutableCopy];
        if (!methodDict)
        {
            methodDict = [NSMutableDictionary dictionary];
        }
        
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(metaType, &methodCount);
        for (const Method *m = methods; m < methods + methodCount; m ++)
        {
            SEL selector = method_getName(*m);
            
            NSString *selectorName = NSStringFromSelector(selector);
            if (![selectorName hasPrefix:@"_"]
                && ![selectorName hasPrefix:@"."]
                && ![excludesMethodNames containsObject:selectorName])
            {
                NSString *luaMethodName = [self _getLuaMethodNameWithSelectorName:selectorName];
                
                //判断是否已导出
                __block BOOL hasExists = NO;
                [LSCEngineAdapter getField:state index:-1 name:luaMethodName.UTF8String];
                if (![LSCEngineAdapter isNil:state index:-1])
                {
                    hasExists = YES;
                }
                [LSCEngineAdapter pop:state count:1];
                
                if (!hasExists)
                {
                    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
                    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
                    [LSCEngineAdapter pushString:luaMethodName.UTF8String state:state];
                    [LSCEngineAdapter pushCClosure:classMethodRouteHandler n:3 state:state];
                    
                    [LSCEngineAdapter setField:state index:-2 name:luaMethodName.UTF8String];
                }
                
                NSMutableArray<LSCExportMethodDescriptor *> *methodList = methodDict[luaMethodName];
                if (!methodList)
                {
                    methodList = [NSMutableArray array];
                    [methodDict setObject:methodList forKey:luaMethodName];
                }
                
                //获取方法签名
                NSString *signStr = [self _getMethodSign:*m];
                
                hasExists = NO;
                [methodList enumerateObjectsUsingBlock:^(LSCExportMethodDescriptor * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                   
                    if ([obj.methodSignature isEqualToString:signStr])
                    {
                        hasExists = YES;
                        *stop = YES;
                    }
                    
                }];
                
                if (!hasExists)
                {
                    LSCExportMethodDescriptor *methodDesc = [[LSCExportMethodDescriptor alloc] init];
                    methodDesc.methodSignature = signStr;
                    
                    NSMethodSignature *sign = [targetTypeDescriptor.nativeType methodSignatureForSelector:selector];
                    methodDesc.invocation = [NSInvocation invocationWithMethodSignature:sign];
                    [methodDesc.invocation setSelector:selector];
                    
                    [methodList addObject:methodDesc];
                }
                
            }
        }
        free(methods);
        
        typeDescriptor.classMethods = methodDict;
    }
    
    //导出父级方法
    LSCExportTypeDescriptor *parentTypeDescriptor = targetTypeDescriptor.parentTypeDescriptor;
    if (parentTypeDescriptor)
    {
        [self _exportsClassMethods:typeDescriptor
                        targetType:parentTypeDescriptor
                             state:state];
    }
}


/**
 导出类方法

 @param typeDescriptor 类型
 @param state Lua状态
 */
- (void)_exportsClassMethods:(LSCExportTypeDescriptor *)typeDescriptor
                       state:(lua_State *)state
{
    [self _exportsClassMethods:typeDescriptor
                    targetType:typeDescriptor
                         state:state];
}


/**
 导出实例方法

 @param typeDescriptor 类型
 @param state Lua状态
 */
- (void)_exportsInstanceMethods:(LSCExportTypeDescriptor *)typeDescriptor
                          state:(lua_State *)state
{
    if (typeDescriptor.nativeType != NULL)
    {
        //注册实例方法
        //先判断是否有注解排除实例方法
        NSArray *excludesMethodNames = nil;
        if (class_conformsToProtocol(typeDescriptor.nativeType, @protocol(LSCExportTypeAnnotation)))
        {
            Class metaType = objc_getMetaClass(NSStringFromClass(typeDescriptor.nativeType).UTF8String);
            if (class_respondsToSelector(metaType, @selector(excludeExportInstanceMethods)))
            {
                excludesMethodNames = [typeDescriptor.nativeType excludeExportInstanceMethods];
            }
        }
        
        //解析方法
        NSMutableDictionary *methodDict = [typeDescriptor.instanceMethods mutableCopy];
        if (!methodDict)
        {
            methodDict = [NSMutableDictionary dictionary];
        }
        
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(typeDescriptor.nativeType, &methodCount);
        for (const Method *m = methods; m < methods + methodCount; m ++)
        {
            SEL selector = method_getName(*m);
            
            NSString *methodName = NSStringFromSelector(selector);
            if (![methodName hasPrefix:@"_"]
                && ![methodName hasPrefix:@"."]
                && ![methodName hasPrefix:@"init"]
                && ![methodName isEqualToString:@"dealloc"]
                && ![excludesMethodNames containsObject:methodName])
            {
                NSString *luaMethodName = [self _getLuaMethodNameWithSelectorName:methodName];
                
                //判断是否已导出
                __block BOOL hasExists = NO;
                [LSCEngineAdapter getField:state index:-1 name:luaMethodName.UTF8String];
                if (![LSCEngineAdapter isNil:state index:-1])
                {
                    hasExists = YES;
                }
                [LSCEngineAdapter pop:state count:1];
                
                if (!hasExists)
                {
                    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
                    [LSCEngineAdapter pushLightUserdata:(__bridge void *)typeDescriptor state:state];
                    [LSCEngineAdapter pushString:luaMethodName.UTF8String state:state];
                    [LSCEngineAdapter pushCClosure:instanceMethodRouteHandler n:3 state:state];
                    
                    [LSCEngineAdapter setField:state index:-2 name:luaMethodName.UTF8String];
                }
                
                NSMutableArray<LSCExportMethodDescriptor *> *methodList = methodDict[luaMethodName];
                if (!methodList)
                {
                    methodList = [NSMutableArray array];
                    [methodDict setObject:methodList forKey:luaMethodName];
                }
                
                //获取方法签名
                NSString *signStr = [self _getMethodSign:*m];
                
                hasExists = NO;
                [methodList enumerateObjectsUsingBlock:^(LSCExportMethodDescriptor * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    
                    if ([obj.methodSignature isEqualToString:signStr])
                    {
                        hasExists = YES;
                        *stop = YES;
                    }
                    
                }];
                
                if (!hasExists)
                {
                    LSCExportMethodDescriptor *methodDesc = [[LSCExportMethodDescriptor alloc] init];
                    methodDesc.methodSignature = signStr;
                    
                    NSMethodSignature *sign = [typeDescriptor.nativeType instanceMethodSignatureForSelector:selector];
                    methodDesc.invocation = [NSInvocation invocationWithMethodSignature:sign];
                    [methodDesc.invocation setSelector:selector];
                    
                    [methodList addObject:methodDesc];
                }
            }
        }
        free(methods);
        
        typeDescriptor.instanceMethods = methodDict;
    }
}

/**
 根据Selector名称获取Lua中的方法名称

 @param selectorName Selector名称
 @return Lua中的方法名
 */
- (NSString *)_getLuaMethodNameWithSelectorName:(NSString *)selectorName
{
    NSString *luaName = selectorName;
    
    NSRange range = [luaName rangeOfString:@":"];
    if (range.location != NSNotFound)
    {
        luaName = [luaName substringToIndex:range.location];
    }
    
    range = [luaName rangeOfString:@"With"];
    if (range.location != NSNotFound)
    {
        luaName = [luaName substringToIndex:range.location];
    }
    
    range = [luaName rangeOfString:@"At"];
    if (range.location != NSNotFound)
    {
        luaName = [luaName substringToIndex:range.location];
    }
    
    range = [luaName rangeOfString:@"By"];
    if (range.location != NSNotFound)
    {
        luaName = [luaName substringToIndex:range.location];
    }
    
    return luaName;
}

/**
 获取类型名称

 @param cls 类型
 @return 名称
 */
- (NSString *)_typeNameWithClass:(Class<LSCExportType>)cls
{
    NSString *name = nil;
    
    //先判断类型是否有进行注解，注：此处必须使用class_conformsToProtocol方法判断，可以具体到指定类型是否实现协议
    //如果使用conformsToProtocol的objc方法则会检测父类是否使用协议，不符合注解规则
    if (class_conformsToProtocol(cls, @protocol(LSCExportTypeAnnotation)))
    {
        if ([self _declareClassMethodResponderToSelector:@selector(typeName) withClass:cls])
        {
            //当前方法实现为
            name = [(id<LSCExportTypeAnnotation>)cls typeName];
        }
    }
    
    if (!name)
    {
        //将类型名称转换为模块名称
        NSString *clsName = NSStringFromClass(cls);
        //Fixed : 由于Swift中类名带有模块名称，因此需要根据.分割字符串，并取最后一部份为导出类名
        NSArray<NSString *> *nameComponents = [clsName componentsSeparatedByString:@"."];
        name = nameComponents.lastObject;
    }
    
    return name;
}

/**
 创建原生对象实例
 
 @param object 类型实例对象
 @param typeDescriptor 类型
 */
- (void)_initLuaObjectWithObject:(id)object type:(LSCExportTypeDescriptor *)typeDescriptor;
{
    lua_State *state = self.context.currentSession.state;
    
    [self _attachLuaInstanceWithNativeObject:object type:typeDescriptor];
    
    //通过_createLuaInstanceWithState方法后会创建实例并放入栈顶
    //调用实例对象的init方法
    [LSCEngineAdapter getField:state index:-1 name:"init"];
    if ([LSCEngineAdapter isFunction:state index:-1])
    {
        [LSCEngineAdapter pushValue:-2 state:state];
        
        //将create传入的参数传递给init方法
        //-3 代表有3个非参数值在栈中，由栈顶开始计算，分别是：实例对象，init方法，实例对象
        int paramCount = [LSCEngineAdapter getTop:state] - 3;
        for (int i = 1; i <= paramCount; i++)
        {
            [LSCEngineAdapter pushValue:i state:state];
        }
        
        [LSCEngineAdapter pCall:state nargs:paramCount + 1 nresults:0 errfunc:0];
    }
    else
    {
        [LSCEngineAdapter pop:state count:1];
    }
}

/**
 将一个原生对象附加到Lua对象中
 
 @param nativeObject 原生实例对象
 @param typeDescriptor 类型描述
 */
- (void)_attachLuaInstanceWithNativeObject:(id)nativeObject
                                      type:(LSCExportTypeDescriptor *)typeDescriptor
{
    lua_State *state = self.context.currentSession.state;
    
    if (nativeObject)
    {
        //先为实例对象在lua中创建内存
        LSCUserdataRef ref = (LSCUserdataRef)[LSCEngineAdapter newUserdata:state size:sizeof(LSCUserdataRef)];
        //创建本地实例对象，赋予lua的内存块并进行保留引用
        ref -> value = (void *)CFBridgingRetain(nativeObject);
    }
    
    //创建一个临时table作为元表，用于在lua上动态添加属性或方法
    [LSCEngineAdapter newTable:state];
    
    [LSCEngineAdapter pushValue:-1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__index"];
    
    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushCClosure:instanceNewIndexHandler n:1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__newindex"];

    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushCClosure:objectDestroyHandler n:1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__gc"];

    [LSCEngineAdapter pushLightUserdata:(__bridge void *)self state:state];
    [LSCEngineAdapter pushCClosure:objectToStringHandler n:1 state:state];
    [LSCEngineAdapter setField:state index:-2 name:"__tostring"];
    
    [LSCEngineAdapter pushValue:-1 state:state];
    [LSCEngineAdapter setMetatable:state index:-3];
    
    [LSCEngineAdapter getMetatable:state name:typeDescriptor.prototypeTypeName.UTF8String];
    if ([LSCEngineAdapter isTable:state index:-1])
    {
        [LSCEngineAdapter setMetatable:state index:-2];
    }
    else
    {
        [LSCEngineAdapter pop:state count:1];
    }
    
    [LSCEngineAdapter pop:state count:1];
}

/**
 查找父级类型描述

 @param typeDescriptor 类型描述
 @return 类型描述
 */
- (LSCExportTypeDescriptor *)_findParentTypeDescriptorWithTypeDescriptor:(LSCExportTypeDescriptor *)typeDescriptor
{
    if (typeDescriptor == self.exportTypes[@"Object"])
    {
        //如果为Object对象，则直接返回空
        return nil;
    }
    
    Class parentType = class_getSuperclass(typeDescriptor.nativeType);
    NSString *parentTypeName = self.exportTypesMapping[NSStringFromClass(parentType)];
    LSCExportTypeDescriptor *parentTypeDescriptor = self.exportTypes[parentTypeName];
    
    if (!parentTypeDescriptor)
    {
        parentTypeDescriptor = self.exportTypes[@"Object"];
    }
    
    //关联关系
    typeDescriptor.parentTypeDescriptor = parentTypeDescriptor;
    
    return parentTypeDescriptor;
}

/**
 返回对象在Lua中的类型描述

 @param object 对象实例
 @return 类型描述，如果为nil则表示非导出类型
 */
- (LSCExportTypeDescriptor *)_typeDescriptorWithObject:(id)object
{
    if ([object conformsToProtocol:@protocol(LSCExportType)])
    {
        NSString *clsName = NSStringFromClass([object class]);
        NSString *typeName = self.exportTypesMapping[clsName];
        return self.exportTypes[typeName];
    }
    
    return nil;
}

/**
 获取调用器

 @param methodName 方法名
 @param arguments 参数列表
 @param typeDesc 类型
 @param isStatic 是否为类方法
 @return 调用器对象
 */
- (NSInvocation *)_invocationWithMethodName:(NSString *)methodName
                                  arguments:(NSArray *)arguments
                                   typeDesc:(LSCExportTypeDescriptor *)typeDesc
                                   isStatic:(BOOL)isStatic
{
    LSCExportMethodDescriptor *methodDesc = nil;
    if (isStatic)
    {
        methodDesc = [typeDesc classMethodWithName:methodName arguments:arguments];
    }
    else
    {
        methodDesc = [typeDesc instanceMethodWithName:methodName arguments:arguments];
    }
    
    return methodDesc.invocation;
}


/**
 获取方法签名

 @param method 方法
 @return 签名字符串
 */
- (NSString *)_getMethodSign:(Method)method
{
    NSMutableString *signStr = [NSMutableString string];
    int argCount = method_getNumberOfArguments(method);
    for (int i = 2; i < argCount; i++)
    {
        char s[256] = {0};
        method_getArgumentType(method, i, s, 256);
        [signStr appendString:[NSString stringWithUTF8String:s]];
    }
    
    return signStr;
}


/**
 判断指定类型是否有定义指定类方法

 @param selector 方法名称
 @param class 类型
 @return YES 表示有实现， NO 表示没有
 */
- (BOOL)_declareClassMethodResponderToSelector:(SEL)selector withClass:(Class)class
{
    Class metaCls = objc_getMetaClass(NSStringFromClass(class).UTF8String);
    
    uint count = 0;
    Method *methodList = class_copyMethodList(metaCls, &count);
    for (int i = 0; i < count; i++)
    {
        if (method_getName(*(methodList + i)) == selector)
        {
            return YES;
        }
    }
    
    free(methodList);
    
    return NO;
}

#pragma mark - C Method

/**
 类方法路由处理器

 @param state 状态
 @return 返回参数数量
 */
static int classMethodRouteHandler(lua_State *state)
{
    int retCount = 0;
    
    //修复float类型在Invocation中会丢失问题，需要定义该结构体来提供给带float参数的方法。同时返回值处理也一样。
    typedef struct {float f;} LSCFloatStruct;
    id obj = nil;
    
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:2];
    ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportTypeDescriptor *typeDescriptor = (__bridge LSCExportTypeDescriptor *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:3];
    const char *methodNameCStr = [LSCEngineAdapter toString:state index:index];
    NSString *methodName = [NSString stringWithUTF8String:methodNameCStr];
    
    LSCSession *callSession = [exporter.context makeSessionWithState:state];
    NSArray *arguments = [callSession parseArguments];
    
    //筛选方法，对于重载方法需要根据lua传入参数进行筛选
    NSInvocation *invocation = [exporter _invocationWithMethodName:methodName
                                                         arguments:arguments
                                                          typeDesc:typeDescriptor
                                                          isStatic:YES];

    //确定调用方法的Target
    if (invocation)
    {
        [invocation setTarget:typeDescriptor.nativeType];
        [invocation retainArguments];
        
        Method m = class_getClassMethod(typeDescriptor.nativeType, invocation.selector);
        for (int i = 2; i < method_getNumberOfArguments(m); i++)
        {
            char *argType = method_copyArgumentType(m, i);
            
            LSCValue *value = nil;
            if (i - 2 < arguments.count)
            {
                value = arguments[i-2];
            }
            else
            {
                value = [LSCValue nilValue];
            }
            
            if (strcmp(argType, @encode(float)) == 0)
            {
                //浮点型数据
                LSCFloatStruct floatValue = {[value toDouble]};
                [invocation setArgument:&floatValue atIndex:i];
            }
            else if (strcmp(argType, @encode(double)) == 0)
            {
                //双精度浮点型
                double doubleValue = [value toDouble];
                [invocation setArgument:&doubleValue atIndex:i];
            }
            else if (strcmp(argType, @encode(int)) == 0
                     || strcmp(argType, @encode(unsigned int)) == 0
                     || strcmp(argType, @encode(long)) == 0
                     || strcmp(argType, @encode(unsigned long)) == 0
                     || strcmp(argType, @encode(short)) == 0
                     || strcmp(argType, @encode(unsigned short)) == 0
                     || strcmp(argType, @encode(char)) == 0
                     || strcmp(argType, @encode(unsigned char)) == 0)
            {
                //整型
                NSInteger intValue = [value toDouble];
                [invocation setArgument:&intValue atIndex:i];
            }
            else if (strcmp(argType, @encode(BOOL)) == 0)
            {
                //布尔类型
                BOOL boolValue = [value toBoolean];
                [invocation setArgument:&boolValue atIndex:i];
            }
            else if (strcmp(argType, @encode(id)) == 0)
            {
                //对象类型
                obj = [value toObject];
                [invocation setArgument:&obj atIndex:i];
            }
            
            free(argType);
        }
        
        [invocation invoke];
        
        char *returnType = method_copyReturnType(m);
        LSCValue *retValue = nil;
        
        if (strcmp(returnType, @encode(id)) == 0)
        {
            //返回值为对象
            id __unsafe_unretained retObj = nil;
            [invocation getReturnValue:&retObj];
            
            retValue = [LSCValue objectValue:retObj];
        }
        else if (strcmp(returnType, @encode(int)) == 0
                 || strcmp(returnType, @encode(unsigned int)) == 0
                 || strcmp(returnType, @encode(long)) == 0
                 || strcmp(returnType, @encode(unsigned long)) == 0
                 || strcmp(returnType, @encode(short)) == 0
                 || strcmp(returnType, @encode(unsigned short)) == 0
                 || strcmp(returnType, @encode(char)) == 0
                 || strcmp(returnType, @encode(unsigned char)) == 0)
        {
            // i 整型
            // I 无符号整型
            // q 长整型
            // Q 无符号长整型
            // S 无符号短整型
            // c 字符型
            // C 无符号字符型
            
            NSInteger intValue = 0;
            [invocation getReturnValue:&intValue];
            retValue = [LSCValue integerValue:intValue];
        }
        else if (strcmp(returnType, @encode(float)) == 0)
        {
            // f 浮点型，需要将值保存到floatStruct结构中传入给方法，否则会导致数据丢失
            LSCFloatStruct floatStruct = {0};
            [invocation getReturnValue:&floatStruct];
            retValue = [LSCValue numberValue:@(floatStruct.f)];
        }
        else if (strcmp(returnType, @encode(double)) == 0)
        {
            // d 双精度浮点型
            double doubleValue = 0.0;
            [invocation getReturnValue:&doubleValue];
            retValue = [LSCValue numberValue:@(doubleValue)];
        }
        else if (strcmp(returnType, @encode(BOOL)) == 0)
        {
            //B 布尔类型
            BOOL boolValue = NO;
            [invocation getReturnValue:&boolValue];
            retValue = [LSCValue booleanValue:boolValue];
        }
        else
        {
            //结构体和其他类型暂时认为和v一样无返回值
            retValue = nil;
        }
        
        free(returnType);
        
        if (retValue)
        {
            retCount = [callSession setReturnValue:retValue];
        }
    }
    else
    {
        NSString *errMsg = [NSString stringWithFormat:@"call `%@` method fail : argument type mismatch", methodName];
        [exporter.context raiseExceptionWithMessage:errMsg];
        return retCount;
    }
    
    return retCount;
}


/**
 实例方法路由处理

 @param state 状态
 @return 参数个数
 */
static int instanceMethodRouteHandler(lua_State *state)
{
    int retCount = 0;
    
    //修复float类型在Invocation中会丢失问题，需要定义该结构体来提供给带float参数的方法。同时返回值处理也一样。
    typedef struct {float f;} LSCFloatStruct;
    
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:2];
    ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportTypeDescriptor *typeDescriptor = (__bridge LSCExportTypeDescriptor *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:3];
    const char *methodNameCStr = [LSCEngineAdapter toString:state index:index];
    NSString *methodName = [NSString stringWithUTF8String:methodNameCStr];
    
    if ([LSCEngineAdapter type:state index:1] != LUA_TUSERDATA)
    {
        NSString *errMsg = [NSString stringWithFormat:@"call %@ method error : missing self parameter, please call by instance:methodName(param)", methodName];
        [exporter.context raiseExceptionWithMessage:errMsg];
        return retCount;
    }
    
    //创建调用会话
    LSCSession *callSession = [exporter.context makeSessionWithState:state];
    NSArray *arguments = [callSession parseArguments];
    id instance = [arguments[0] toObject];
    
    NSInvocation *invocation = [exporter _invocationWithMethodName:methodName
                                                         arguments:arguments
                                                          typeDesc:typeDescriptor
                                                          isStatic:NO];

    //获取类实例对象
    if (invocation && instance)
    {
        [invocation setTarget:instance];
        [invocation retainArguments];
        
        Method m = class_getInstanceMethod(typeDescriptor.nativeType, invocation.selector);
        for (int i = 2; i < method_getNumberOfArguments(m); i++)
        {
            char *argType = method_copyArgumentType(m, i);
            
            LSCValue *value = nil;
            if (i - 1 < arguments.count)
            {
                value = arguments[i - 1];
            }
            else
            {
                value = [LSCValue nilValue];
            }
            
            if (strcmp(argType, @encode(float)) == 0)
            {
                //浮点型数据
                LSCFloatStruct floatValue = {[value toDouble]};
                [invocation setArgument:&floatValue atIndex:i];
            }
            else if (strcmp(argType, @encode(double)) == 0)
            {
                //双精度浮点型
                double doubleValue = [value toDouble];
                [invocation setArgument:&doubleValue atIndex:i];
            }
            else if (strcmp(argType, @encode(int)) == 0
                     || strcmp(argType, @encode(unsigned int)) == 0
                     || strcmp(argType, @encode(long)) == 0
                     || strcmp(argType, @encode(unsigned long)) == 0
                     || strcmp(argType, @encode(short)) == 0
                     || strcmp(argType, @encode(unsigned short)) == 0
                     || strcmp(argType, @encode(char)) == 0
                     || strcmp(argType, @encode(unsigned char)) == 0)
            {
                //整型
                NSInteger intValue = [value toDouble];
                [invocation setArgument:&intValue atIndex:i];
            }
            else if (strcmp(argType, @encode(BOOL)) == 0)
            {
                //布尔类型
                BOOL boolValue = [value toBoolean];
                [invocation setArgument:&boolValue atIndex:i];
            }
            else if (strcmp(argType, @encode(id)) == 0)
            {
                //对象类型
                id obj = [value toObject];
                [invocation setArgument:&obj atIndex:i];
            }
            
            free(argType);
        }
        
        [invocation invoke];
        
        char *returnType = method_copyReturnType(m);
        
        LSCValue *retValue = nil;
        if (strcmp(returnType, @encode(id)) == 0)
        {
            //返回值为对象，添加__unsafe_unretained修饰用于修复ARC下retObj对象被释放问题。
            id __unsafe_unretained retObj = nil;
            [invocation getReturnValue:&retObj];
            
            retValue = [LSCValue objectValue:retObj];
        }
        else if (strcmp(returnType, @encode(int)) == 0
                 || strcmp(returnType, @encode(unsigned int)) == 0
                 || strcmp(returnType, @encode(long)) == 0
                 || strcmp(returnType, @encode(unsigned long)) == 0
                 || strcmp(returnType, @encode(short)) == 0
                 || strcmp(returnType, @encode(unsigned short)) == 0
                 || strcmp(returnType, @encode(char)) == 0
                 || strcmp(returnType, @encode(unsigned char)) == 0)
        {
            // i 整型
            // I 无符号整型
            // q 长整型
            // Q 无符号长整型
            // S 无符号短整型
            // c 字符型
            // C 无符号字符型
            
            NSInteger intValue = 0;
            [invocation getReturnValue:&intValue];
            retValue = [LSCValue integerValue:intValue];
        }
        else if (strcmp(returnType, @encode(float)) == 0)
        {
            // f 浮点型，需要将值保存到floatStruct结构中传入给方法，否则会导致数据丢失
            LSCFloatStruct floatStruct = {0};
            [invocation getReturnValue:&floatStruct];
            retValue = [LSCValue numberValue:@(floatStruct.f)];
            
        }
        else if (strcmp(returnType, @encode(double)) == 0)
        {
            // d 双精度浮点型
            double doubleValue = 0.0;
            [invocation getReturnValue:&doubleValue];
            retValue = [LSCValue numberValue:@(doubleValue)];
        }
        else if (strcmp(returnType, @encode(BOOL)) == 0)
        {
            //B 布尔类型
            BOOL boolValue = NO;
            [invocation getReturnValue:&boolValue];
            retValue = [LSCValue booleanValue:boolValue];
        }
        else
        {
            //nil
            retValue = nil;
        }
        
        free(returnType);
        
        if (retValue)
        {
            retCount = [callSession setReturnValue:retValue];
        }
        
    }
    else
    {
        NSString *errMsg = [NSString stringWithFormat:@"call `%@` method fail : argument type mismatch", methodName];
        [exporter.context raiseExceptionWithMessage:errMsg];
        return retCount;
    }
    
    return retCount;
}

/**
 *  创建对象时处理
 *
 *  @param state 状态机
 *
 *  @return 参数数量
 */
static int objectCreateHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:2];
    ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportTypeDescriptor *typeDescriptor = (__bridge LSCExportTypeDescriptor *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    //创建对象
    id instance = nil;
    if (typeDescriptor.nativeType != NULL)
    {
        instance = [[typeDescriptor.nativeType alloc] init];
    }
    
    [exporter _initLuaObjectWithObject:instance type:typeDescriptor];
    
    session = nil;
    
    return 1;
}

/**
 实例对象更新索引处理
 
 @param state 状态机
 @return 参数数量
 */
static int instanceNewIndexHandler (lua_State *state)
{
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)[LSCEngineAdapter toPointer:state
                                                                                  index:[LSCEngineAdapter upvalueIndex:1]];
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    //先找到实例对象的元表，向元表添加属性
    [LSCEngineAdapter getMetatable:state index:1];
    if ([LSCEngineAdapter isTable:state index:-1])
    {
        [LSCEngineAdapter pushValue:2 state:state];
        [LSCEngineAdapter pushValue:3 state:state];
        [LSCEngineAdapter rawSet:state index:-3];
    }
    
    session = nil;
    
    return 0;
}

/**
 *  对象销毁处理
 *
 *  @param state 状态机
 *
 *  @return 参数数量
 */
static int objectDestroyHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    if ([LSCEngineAdapter getTop:state] > 0 && [LSCEngineAdapter isUserdata:state index:1])
    {
        //如果为userdata类型，则进行释放
        LSCUserdataRef ref = (LSCUserdataRef)[LSCEngineAdapter toUserdata:state index:1];
        
        [LSCEngineAdapter pushValue:1 state:state];
        [LSCEngineAdapter getField:state index:-1 name:"destroy"];
        if ([LSCEngineAdapter isFunction:state index:-1])
        {
            [LSCEngineAdapter pushValue:1 state:state];
            [LSCEngineAdapter pCall:state nargs:1 nresults:0 errfunc:0];
        }
        else
        {
            [LSCEngineAdapter pop:state count:1];
        }
        [LSCEngineAdapter pop:state count:1];
        
        //释放内存
        CFBridgingRelease(ref -> value);
    }
    
    session = nil;
    
    return 0;
}


/**
 类型转换为字符串处理

 @param state 状态
 @return 参数数量
 */
static int classToStringHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    LSCExportTypeDescriptor *typeDescriptor = nil;
    
    [LSCEngineAdapter getField:state index:1 name:"_nativeType"];
    if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
    {
        typeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
    }
    
    if (typeDescriptor)
    {
        [LSCEngineAdapter pushString:[[NSString stringWithFormat:@"[%@ type]", typeDescriptor.typeName] UTF8String] state:state];
    }
    else
    {
        [exporter.context raiseExceptionWithMessage:@"Can not describe unknown type."];
        [LSCEngineAdapter pushNil:state];
    }
    
    session = nil;
    
    return 1;
}

/**
 转换Prototype为字符串处理

 @param state 状态
 @return 参数数量
 */
static int prototypeToStringHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    LSCExportTypeDescriptor *typeDescriptor = nil;
    
    [LSCEngineAdapter getField:state index:1 name:"_nativeType"];
    if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
    {
        typeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
    }
    
    if (typeDescriptor)
    {
        [LSCEngineAdapter pushString:[[NSString stringWithFormat:@"[%@ prototype]", typeDescriptor.typeName] UTF8String] state:state];
    }
    else
    {
        [exporter.context raiseExceptionWithMessage:@"Can not describe unknown prototype."];
        [LSCEngineAdapter pushNil:state];
    }
    
    session = nil;
    
    return 1;
}

/**
 *  对象转换为字符串处理
 *
 *  @param state 状态机
 *
 *  @return 参数数量
 */
static int objectToStringHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    LSCExportTypeDescriptor *typeDescriptor = nil;
    
    [LSCEngineAdapter getField:state index:1 name:"_nativeType"];
    if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
    {
        typeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
    }
    
    if (typeDescriptor)
    {
        [LSCEngineAdapter pushString:[[NSString stringWithFormat:@"[%@ object]", typeDescriptor.typeName] UTF8String] state:state];
    }
    else
    {
        [exporter.context raiseExceptionWithMessage:@"Can not describe unknown object."];
        [LSCEngineAdapter pushNil:state];
    }
    
    session = nil;
    
    return 1;
}

/**
 *  子类化
 *
 *  @param state 状态机
 *
 *  @return 参数数量
 */
static int subClassHandler (lua_State *state)
{
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:2];
    ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportTypeDescriptor *typeDescriptor = (__bridge LSCExportTypeDescriptor *)ptr;
    
    if ([LSCEngineAdapter getTop:state] == 0)
    {
        [exporter.context raiseExceptionWithMessage:@"Miss the subclass name parameter"];
        return 0;
    }
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    //构建子类型描述
    NSString *typeName = [NSString stringWithUTF8String:[LSCEngineAdapter checkString:state index:1]];
    LSCExportTypeDescriptor *subTypeDescriptor = [[LSCExportTypeDescriptor alloc] initWithTypeName:typeName nativeType:typeDescriptor.nativeType];
    subTypeDescriptor.parentTypeDescriptor = typeDescriptor;
    [exporter.exportTypes setObject:subTypeDescriptor forKey:subTypeDescriptor.typeName];
    
    [exporter _exportsType:subTypeDescriptor state:state];
    
    session = nil;
    
    return 0;
}

/**
 判断是否是该类型的子类
 
 @param state 状态机
 @return 参数数量
 */
static int subclassOfHandler (lua_State *state)
{
    if ([LSCEngineAdapter getTop:state] == 0)
    {
        [LSCEngineAdapter pushBoolean:NO state:state];
        return 1;
    }
    
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;
    
    index = [LSCEngineAdapter upvalueIndex:2];
    ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportTypeDescriptor *typeDescriptor = (__bridge LSCExportTypeDescriptor *)ptr;
    
    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    if ([LSCEngineAdapter type:state index:1] == LUA_TTABLE)
    {
        [LSCEngineAdapter getField:state index:1 name:"_nativeType"];
        if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
        {
            LSCExportTypeDescriptor *checkTypeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
        
            BOOL flag = [typeDescriptor subtypeOfType:checkTypeDescriptor];
            [LSCEngineAdapter pushBoolean:flag state:state];
            
            return 1;
        }
    }
    
    [LSCEngineAdapter pushBoolean:NO state:state];
    
    session = nil;
    
    return 1;
}

/**
 判断是否是该类型的实例对象
 
 @param state 状态机
 @return 参数数量
 */
static int instanceOfHandler (lua_State *state)
{
    if ([LSCEngineAdapter getTop:state] < 2)
    {
        [LSCEngineAdapter pushBoolean:NO state:state];
        return 1;
    }
    
    int index = [LSCEngineAdapter upvalueIndex:1];
    const void *ptr = [LSCEngineAdapter toPointer:state index:index];
    LSCExportsTypeManager *exporter = (__bridge LSCExportsTypeManager *)ptr;

    LSCSession *session = [exporter.context makeSessionWithState:state];
    
    //获取实例类型
    LSCExportTypeDescriptor *typeDescriptor = nil;
    [LSCEngineAdapter getField:state index:1 name:"_nativeType"];
    if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
    {
        typeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
    }
    [LSCEngineAdapter pop:state count:1];
    
    if (typeDescriptor)
    {
        if ([LSCEngineAdapter type:state index:2] == LUA_TTABLE)
        {
            [LSCEngineAdapter getField:state index:2 name:"_nativeType"];
            if ([LSCEngineAdapter type:state index:-1] == LUA_TLIGHTUSERDATA)
            {
                LSCExportTypeDescriptor *checkTypeDescriptor = (__bridge LSCExportTypeDescriptor *)[LSCEngineAdapter toPointer:state index:-1];
                BOOL flag = [typeDescriptor subtypeOfType:checkTypeDescriptor];
                
                [LSCEngineAdapter pushBoolean:flag state:state];
                
                return 1;
            }
        }
    }
    
    
    [LSCEngineAdapter pushBoolean:NO state:state];
    
    session = nil;
    
    return 1;
}

/**
 全局对象的index元方法处理

 @param state 状态
 @return 返回参数数量
 */
static int globalIndexMetaMethodHandler(lua_State *state)
{
    LSCExportsTypeManager *exportsTypeManager = [LSCEngineAdapter toPointer:state index:[LSCEngineAdapter upvalueIndex:1]];
    
    //获取key
    NSString *key = [NSString stringWithUTF8String:[LSCEngineAdapter toString:state index:2]];
    
    [LSCEngineAdapter rawGet:state index:1];
    if ([LSCEngineAdapter isNil:state index:-1])
    {
        //检测是否该key是否为导出类型
        LSCExportTypeDescriptor *typeDescriptor = exportsTypeManager.exportTypes[key];
        if (typeDescriptor)
        {
            //为导出类型
            [LSCEngineAdapter pop:state count:1];
            
            [exportsTypeManager _prepareExportsTypeWithDescriptor:typeDescriptor];
            
            //重新获取
            [LSCEngineAdapter pushString:key.UTF8String state:state];
            [LSCEngineAdapter rawGet:state index:1];
        }
    }
    
    return 1;
}

@end
