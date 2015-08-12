import std.stdio;
import std.algorithm;
import parser;
import Record;
import typedecl;
import std.range;
import FunctionSig;

Type* instantiateAggregate(RecordBuilder records, AggregateType* aggregate)
{
    auto type = new Type();
    if (aggregate.typeName in records.structDefs)
    {
        auto structDef = records.structDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != structDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(structDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        type.tag = TypeEnum.STRUCT;
        type.structDef = structDef;
        type = type.instantiateTypeTemplate(mappings, records);
    }
    else if (aggregate.typeName in records.variantDefs)
    {
        auto variantDef = records.variantDefs[aggregate.typeName].copy;
        Type*[string] mappings;
        if (aggregate.templateInstantiations.length
            != variantDef.templateParams.length)
        {
            throw new Exception("Template instantiation count mismatch.");
        }
        else
        {
            foreach (var, type; lockstep(variantDef.templateParams,
                                    aggregate.templateInstantiations))
            {
                mappings[var] = type.copy;
            }
        }
        type.tag = TypeEnum.VARIANT;
        type.variantDef = variantDef;
        type = type.instantiateTypeTemplate(mappings, records);
    }
    else
    {
        throw new Exception(
            "Instantiation of non-existent type:\n"
            ~ "  " ~ aggregate.typeName
        );
    }
    return type;
}

Type* normalizeStructDefs(RecordBuilder records, StructType* structType)
{
    auto structCopy = structType.copy;
    foreach (ref member; structCopy.members)
    {
        if (member.type.tag == TypeEnum.AGGREGATE)
        {
            if (member.type.aggregate.typeName in records.structDefs)
            {
                member.type = instantiateAggregate(
                    records, member.type.aggregate
                );
            }
            else if (member.type.aggregate.typeName in records.variantDefs)
            {
                member.type = instantiateAggregate(
                    records, member.type.aggregate
                );
            }
            else
            {
                throw new Exception("Cannot normalize struct def");
            }
        }
    }
    auto type = new Type();
    type.tag = TypeEnum.STRUCT;
    type.structDef = structCopy;
    return type;
}

Type* normalizeVariantDefs(RecordBuilder records, VariantType* variantType)
{
    foreach (ref member; variantType.members)
    {
        if (member.constructorElems.tag != TypeEnum.TUPLE)
        {
            continue;
        }
        foreach (ref elemType; member.constructorElems.tuple.types)
        {
            if (elemType.tag == TypeEnum.AGGREGATE)
            {
                if (elemType.aggregate.typeName == variantType.name
                    && compareAggregateToVariant(elemType.aggregate,
                                                 variantType))
                {
                    auto wrap = new Type();
                    wrap.tag = TypeEnum.VARIANT;
                    wrap.variantDef = variantType;
                    elemType = wrap;
                }
                else if (elemType.aggregate.typeName in records.structDefs)
                {
                    elemType = instantiateAggregate(
                        records, elemType.aggregate
                    );
                }
                else if (elemType.aggregate.typeName in records.variantDefs)
                {
                    elemType = instantiateAggregate(
                        records, elemType.aggregate
                    );
                }
                else
                {
                    throw new Exception("Cannot normalize variant def");
                }
            }
        }
    }
    auto type = new Type();
    type.tag = TypeEnum.VARIANT;
    type.variantDef = variantType;
    return type;
}

Type* normalize(Type* type, RecordBuilder records)
{
    if (type.tag == TypeEnum.AGGREGATE)
    {
        type = instantiateAggregate(records, type.aggregate);
    }
    if (type.tag == TypeEnum.STRUCT)
    {
        type = normalizeStructDefs(records, type.structDef);
    }
    if (type.tag == TypeEnum.VARIANT)
    {
        type = normalizeVariantDefs(records, type.variantDef);
    }
    if (type.tag == TypeEnum.ARRAY)
    {
        type.array.arrayType = normalize(type.array.arrayType, records);
    }
    if (type.tag == TypeEnum.SET)
    {
        type.set.setType = normalize(type.set.setType, records);
    }
    if (type.tag == TypeEnum.HASH)
    {
        type.hash.keyType = normalize(type.hash.keyType, records);
        type.hash.valueType = normalize(type.hash.valueType, records);
    }
    return type;
}

Type* instantiateTypeTemplate(Type* templatedType, Type*[string] mappings,
                              RecordBuilder records)
{
    Type*[] instantiatedTypes;

    Type* _instantiateTypeTemplate(Type* type)
    {
        final switch (type.tag)
        {
        case TypeEnum.VOID:
        case TypeEnum.LONG:
        case TypeEnum.INT:
        case TypeEnum.SHORT:
        case TypeEnum.BYTE:
        case TypeEnum.FLOAT:
        case TypeEnum.DOUBLE:
        case TypeEnum.CHAR:
        case TypeEnum.BOOL:
        case TypeEnum.STRING:
        case TypeEnum.TUPLE:
        case TypeEnum.FUNCPTR:
            break;
        case TypeEnum.AGGREGATE:
            foreach (ref t; type.aggregate.templateInstantiations)
            {
                if (t.tag == TypeEnum.AGGREGATE
                    && t.aggregate.typeName in mappings)
                {
                    t = mappings[t.aggregate.typeName];
                }
            }
            return type;
        case TypeEnum.SET:
            if (type.set.setType.tag == TypeEnum.AGGREGATE
                && type.set.setType.aggregate.typeName in mappings)
            {
                type.set.setType
                    = mappings[type.set.setType.aggregate.typeName];
            }
            break;
        case TypeEnum.HASH:
            if (type.hash.keyType.tag == TypeEnum.AGGREGATE
                && type.hash.keyType.aggregate.typeName in mappings)
            {
                type.hash.keyType
                    = mappings[type.hash.keyType.aggregate.typeName];
            }
            if (type.hash.valueType.tag == TypeEnum.AGGREGATE
                && type.hash.valueType.aggregate.typeName in mappings)
            {
                type.hash.valueType
                    = mappings[type.hash.valueType.aggregate.typeName];
            }
            break;
        case TypeEnum.ARRAY:
            if (type.array.arrayType.tag == TypeEnum.AGGREGATE
                && type.array.arrayType.aggregate.typeName in mappings)
            {
                type.array.arrayType
                    = mappings[type.array.arrayType.aggregate.typeName];
            }
            else if (type.array.arrayType.tag == TypeEnum.AGGREGATE)
            {
                type.array.arrayType = _instantiateTypeTemplate(
                    type.array.arrayType
                );
            }
            break;
        case TypeEnum.CHAN:
            if (type.chan.chanType.tag == TypeEnum.AGGREGATE
                && type.chan.chanType.aggregate.typeName in mappings)
            {
                type.chan.chanType
                    = mappings[type.chan.chanType.aggregate.typeName];
            }
            break;
        case TypeEnum.VARIANT:
            foreach (ref member; type.variantDef.members)
            {
                auto typeTuple = member.constructorElems
                                       .copy;
                Type*[] instantiations;
                foreach (memberType; typeTuple.tuple.types)
                {
                    if (memberType.tag == TypeEnum.AGGREGATE
                        && memberType.aggregate.typeName in mappings)
                    {
                        instantiations
                            ~= mappings[memberType.aggregate.typeName];
                    }
                    else
                    {
                        instantiations ~= _instantiateTypeTemplate(
                            memberType
                        );
                    }
                }
                typeTuple.tuple.types = instantiations;
                member.constructorElems = typeTuple;
            }
            type.variantDef.instantiated = true;
            break;
        case TypeEnum.STRUCT:
            foreach (ref member; type.structDef.members)
            {
                auto memberType = member.type.copy;
                if (memberType.tag == TypeEnum.AGGREGATE
                    && memberType.aggregate.typeName in mappings)
                {
                    memberType = mappings[memberType.aggregate.typeName];
                }
                else
                {
                    memberType = _instantiateTypeTemplate(memberType);
                }
                member.type = memberType;
            }
            type.structDef.instantiated = true;
            break;
        }
        return type;
    }

    auto type = templatedType.copy;
    final switch (type.tag)
    {
    case TypeEnum.VOID:
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
    case TypeEnum.CHAR:
    case TypeEnum.BOOL:
    case TypeEnum.STRING:
    case TypeEnum.AGGREGATE:
    case TypeEnum.FUNCPTR:
        break;
    case TypeEnum.SET:
        type.set.setType = _instantiateTypeTemplate(type.set.setType);
        break;
    case TypeEnum.HASH:
        type.hash.keyType = _instantiateTypeTemplate(type.hash.keyType);
        type.hash.valueType = _instantiateTypeTemplate(type.hash.valueType);
        break;
    case TypeEnum.ARRAY:
        type.array.arrayType = _instantiateTypeTemplate(type.array.arrayType);
        break;
    case TypeEnum.TUPLE:
        foreach (ref tupleType; type.tuple.types)
        {
            tupleType = _instantiateTypeTemplate(tupleType);
        }
        break;
    case TypeEnum.CHAN:
        if (type.chan.chanType.tag == TypeEnum.AGGREGATE
            && type.chan.chanType.aggregate.typeName in mappings)
        {
            type.chan.chanType
                = mappings[type.chan.chanType.aggregate.typeName];
        }
        break;
    case TypeEnum.VARIANT:
        type.variantDef.mappings = mappings;
        auto missing = mappings.keys
                               .sort
                               .setSymmetricDifference(type.variantDef
                                                           .templateParams
                                                           .sort);
        if (missing.walkLength > 0)
        {
            auto str = q"EOF
instantiateTypeTemplate(): The passed mapping does not contain keys that
correspond exactly with the known template parameter names. Not attempting to
instantiate. The missing mappings are:
EOF";
            foreach (name; missing)
            {
                str ~= "  " ~ name ~ "\n";
            }
            throw new Exception(str);
        }
        foreach (ref member; type.variantDef.members)
        {
            auto typeTuple = member.constructorElems;
            Type*[] instantiations;
            if (typeTuple.tag == TypeEnum.TUPLE)
            {
                foreach (memberType; typeTuple.tuple.types)
                {
                    if (memberType.tag == TypeEnum.AGGREGATE
                        && memberType.aggregate.typeName in mappings)
                    {
                        instantiations
                            ~= mappings[memberType.aggregate.typeName];
                    }
                    else if (memberType.tag == TypeEnum.AGGREGATE
                        && memberType.aggregate.typeName == type.variantDef.name)
                    {
                        instantiations ~= type;
                    }
                    else
                    {
                        instantiations ~= _instantiateTypeTemplate(
                            memberType
                        );
                    }
                }
                typeTuple.tuple.types = instantiations;
            }
            member.constructorElems = typeTuple;
        }
        type.variantDef.instantiated = true;
        break;
    case TypeEnum.STRUCT:
        type.structDef.mappings = mappings;
        auto missing = mappings.keys
                               .sort
                               .setSymmetricDifference(type.structDef
                                                           .templateParams
                                                           .sort);
        if (missing.walkLength > 0)
        {
            auto str = q"EOF
instantiateTypeTemplate(): The passed mapping does not contain keys that
correspond exactly with the known template parameter names. Not attempting to
instantiate. The missing mappings are:
EOF";
            foreach (name; missing)
            {
                str ~= "  " ~ name ~ "\n";
            }
            throw new Exception(str);
        }
        foreach (ref member; type.structDef.members)
        {
            auto memberType = member.type;
            if (memberType.tag == TypeEnum.AGGREGATE
                && memberType.aggregate.typeName in mappings)
            {
                memberType = mappings[memberType.aggregate.typeName];
            }
            else if (memberType.tag == TypeEnum.AGGREGATE
                && memberType.aggregate.typeName == type.structDef.name)
            {
                auto str = "";
                str ~= "struct definition ["
                    ~ type.structDef.name
                    ~ "] contains an illegal self-reference in member "
                    ~ member.name;
                throw new Exception(str);
            }
            else
            {
                memberType = _instantiateTypeTemplate(memberType);
            }
            member.type = memberType;
        }
        type.structDef.instantiated = true;
        break;
    }
    return type;
}

VariantType* variantFromConstructor(RecordBuilder records, string constructor)
{
    auto variantDefs = records.variantDefs;
    foreach (def; variantDefs)
    {
        foreach (member; def.members)
        {
            if (member.constructorName == constructor)
            {
                return def;//normalizeVariantDefs(records, def).variantDef;
            }
        }
    }
    return null;
}

struct FuncSigLookupResult
{
    FuncSig* sig;
    bool success;

    this (bool success = false)
    {
        this.success = success;
    }

    this (FuncSig* sig)
    {
        this.sig = sig;
        this.success = true;
    }
}

auto funcSigLookup(FuncSig*[] sigs, string name)
{
    foreach (sig; sigs)
    {
        if (name == sig.funcName)
        {
            return FuncSigLookupResult(sig);
        }
    }
    return FuncSigLookupResult();
}

bool compareAggregateToVariant(AggregateType* aggregate, VariantType* variant)
{
    if (aggregate.typeName != variant.name)
    {
        return false;
    }
    // Check if they have the same number of template arguments. If the name
    // check passed, something is terribly wrong for this to fail
    if (aggregate.templateInstantiations.length
        != variant.templateParams.length)
    {
        return false;
    }
    // Same number of template arguments, so if it's zero, then they're the same
    if (aggregate.templateInstantiations.length == 0)
    {
        return true;
    }
    foreach (aggTemplateType, varTemplateName;
             lockstep(aggregate.templateInstantiations,
                      variant.templateParams))
    {
        if (!aggTemplateType.cmp(variant.mappings[varTemplateName]))
        {
            return false;
        }
    }
    return true;
}

// If the type is an aggregate, return true. If the type is a templated struct
// or variant definition, but has not been instantiated, return true.
// Otherwise, return false
bool isUninstantiated(Type* type)
{
    if (   (   type.tag == TypeEnum.VARIANT
           &&  type.variantDef.templateParams.length > 0
           && !type.variantDef.instantiated)
        || (   type.tag == TypeEnum.STRUCT
           &&  type.structDef.templateParams.length > 0
           && !type.structDef.instantiated)
        || (   type.tag == TypeEnum.AGGREGATE))
    {
        return true;
    }
    return false;
}

ASTNonTerminal genTypeTree(string templateParam, Type* newType)
{
    final switch (newType.tag)
    {
    case TypeEnum.VOID:
    case TypeEnum.LONG:
    case TypeEnum.INT:
    case TypeEnum.SHORT:
    case TypeEnum.BYTE:
    case TypeEnum.FLOAT:
    case TypeEnum.DOUBLE:
    case TypeEnum.CHAR:
    case TypeEnum.BOOL:
    case TypeEnum.STRING:
        // Perform tree replacement for basic type
        auto newNode = new BasicTypeNode();
        auto newTerminalNode = new ASTTerminal(
            newType.format, 0
        );
        newNode.children ~= newTerminalNode;
        return newNode;
    case TypeEnum.SET:
        auto newNode = new SetTypeNode();
        newNode.children ~= genTypeTree(templateParam, newType.set.setType);
        return newNode;
    case TypeEnum.HASH:
        auto newNode = new HashTypeNode();
        newNode.children ~= genTypeTree(templateParam, newType.hash.keyType);
        auto valueNode = new TypeIdNode;
        valueNode.children ~= genTypeTree(
            templateParam, newType.hash.valueType
        );
        newNode.children ~= valueNode;
        return newNode;
    case TypeEnum.ARRAY:
        auto newNode = new ArrayTypeNode();
        auto typeIdNode = new TypeIdNode();
        typeIdNode.children ~= genTypeTree(
            templateParam, newType.array.arrayType
        );
        newNode.children ~= typeIdNode;
        return newNode;
    case TypeEnum.CHAN:
        auto newNode = new ChanTypeNode();
        auto typeIdNode = new TypeIdNode();
        typeIdNode.children ~= genTypeTree(
            templateParam, newType.chan.chanType
        );
        newNode.children ~= typeIdNode;
        return newNode;
    case TypeEnum.STRUCT:
        auto newNode = new UserTypeNode();
        auto idNode = new IdentifierNode();
        auto termNode = new ASTTerminal(newType.structDef.name, 0);
        idNode.children ~= termNode;
        newNode.children ~= idNode;
        if (newType.structDef.templateParams.length > 0)
        {
            auto templateInstanceNode = new TemplateInstantiationNode();
            auto templateParamNode = new TemplateParamNode();
            if (newType.structDef.templateParams.length > 1)
            {
                auto paramList = new TemplateParamListNode();
                foreach (param; newType.structDef.templateParams)
                {
                    auto aliasNode = new TemplateAliasNode();

                    // TODO do we need to do something about the lambda option
                    // here?

                    auto aliasTypeIdNode = new TypeIdNode;
                    aliasTypeIdNode.children ~= genTypeTree(
                        templateParam, newType.structDef.mappings[param]
                    );
                    aliasNode.children ~= aliasTypeIdNode;
                    paramList.children ~= aliasNode;
                }
                templateParamNode.children ~= paramList;
            }
            else
            {
                auto templateTypeIdNode = new TypeIdNode();
                templateTypeIdNode.children ~= genTypeTree(
                    templateParam,
                    newType.structDef
                           .mappings[newType.structDef.templateParams[0]]
                );
                templateParamNode.children ~= templateTypeIdNode;
            }
            templateInstanceNode.children ~= templateParamNode;
            newNode.children ~= templateInstanceNode;
        }
        return newNode;
    case TypeEnum.VARIANT:
        auto newNode = new UserTypeNode();
        auto idNode = new IdentifierNode();
        auto termNode = new ASTTerminal(newType.variantDef.name, 0);
        idNode.children ~= termNode;
        newNode.children ~= idNode;
        if (newType.variantDef.templateParams.length > 0)
        {
            auto templateInstanceNode = new TemplateInstantiationNode();
            auto templateParamNode = new TemplateParamNode();
            if (newType.variantDef.templateParams.length > 1)
            {
                auto paramList = new TemplateParamListNode();
                foreach (param; newType.variantDef.templateParams)
                {
                    auto aliasNode = new TemplateAliasNode();

                    // TODO do we need to do something about the lambda option
                    // here?

                    auto aliasTypeIdNode = new TypeIdNode;
                    aliasTypeIdNode.children ~= genTypeTree(
                        templateParam, newType.variantDef.mappings[param]
                    );
                    aliasNode.children ~= aliasTypeIdNode;
                    paramList.children ~= aliasNode;
                }
                templateParamNode.children ~= paramList;
            }
            else
            {
                auto templateTypeIdNode = new TypeIdNode();
                templateTypeIdNode.children ~= genTypeTree(
                    templateParam,
                    newType.variantDef
                           .mappings[newType.variantDef.templateParams[0]]
                );
                templateParamNode.children ~= templateTypeIdNode;
            }
            templateInstanceNode.children ~= templateParamNode;
            newNode.children ~= templateInstanceNode;
        }
        return newNode;
    case TypeEnum.AGGREGATE:
        assert(false, "Unreachable");
        break;
    case TypeEnum.FUNCPTR:
    case TypeEnum.TUPLE:
        assert(false, "Unimplemented");
        break;
    }
}

string getMangledFuncName(FuncSig* sig)
{
    auto str = "";
    str ~= "__";
    str ~= sig.funcName;
    str ~= "??";
    foreach (type; sig.templateTypes)
    {
        str ~= type.formatMangle();
    }
    str ~= "##";
    foreach (var; sig.funcArgs)
    {
        str ~= var.type.formatMangle();
    }
    return str;
}
