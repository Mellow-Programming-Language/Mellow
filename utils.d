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
        throw new Exception("Instantiation of non-existent type.");
    }
    return type;
}

Type* normalizeStructDefs(RecordBuilder records, StructType* structType)
{
    auto structCopy = structType.copy;
    structCopy.formatFull.writeln;
    foreach (ref member; structCopy.members)
    {
        if (member.type.tag == TypeEnum.AGGREGATE)
        {
            if (member.type.aggregate.typeName in records.structDefs)
            {
                auto instance = new Type();
                instance.tag = TypeEnum.STRUCT;
                instance.structDef =
                    records.structDefs[member.type.aggregate.typeName].copy;
                member.type = instance;
            }
            else if (member.type.aggregate.typeName in records.variantDefs)
            {
                auto instance = new Type();
                instance.tag = TypeEnum.VARIANT;
                instance.variantDef =
                    records.variantDefs[member.type.aggregate.typeName].copy;
                member.type = instance;
            }
            else
            {
                member.type.formatFull.writeln;
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
    "normalizeVariantDefs()".writeln;
    foreach (ref member; variantType.members)
    {
        if (member.constructorElems.tag != TypeEnum.TUPLE)
        {
            continue;
        }
        foreach (ref elemType; member.constructorElems.tuple.types)
        {
            "loop".writeln;
            if (elemType.tag == TypeEnum.AGGREGATE)
            {
                if (elemType.aggregate.typeName == variantType.name)
                {
                    "hit this guy".writeln;
                    auto wrap = new Type();
                    wrap.tag = TypeEnum.VARIANT;
                    wrap.variantDef = variantType;
                    elemType = wrap;
                }
                else if (elemType.aggregate.typeName in records.structDefs)
                {
                    "nah this one".writeln;
                    auto instance = new Type();
                    instance.tag = TypeEnum.STRUCT;
                    instance.structDef =
                        records.structDefs[elemType.aggregate.typeName].copy;
                    elemType = instance;
                }
                else if (elemType.aggregate.typeName in records.variantDefs)
                {
                    "nah THIS guy".writeln;
                    auto wrap = new Type();
                    wrap.tag = TypeEnum.VARIANT;
                    wrap.variantDef =
                        records.variantDefs[elemType.aggregate.typeName].copy;
                    elemType = wrap;
                }
                else
                {
                    throw new Exception("Cannot normalize struct def");
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
    type = type.copy;
    if (type.tag == TypeEnum.AGGREGATE)
    {
        "      normalizing aggregate".writeln;
        type = instantiateAggregate(records, type.aggregate);
    }
    if (type.tag == TypeEnum.STRUCT)
    {
        "      normalizing struct".writeln;
        type = normalizeStructDefs(records, type.structDef);
    }
    if (type.tag == TypeEnum.VARIANT)
    {
        "      normalizing variant".writeln;
        type = normalizeVariantDefs(records, type.variantDef);
    }
    return type;
}

Type* instantiateTypeTemplate(Type* templatedType, Type*[string] mappings,
                              RecordBuilder records)
{
    Type*[] instantiatedTypes;

    Type* findExistingInstantiation(AggregateType* dummyType)
    {
        foreach (type; instantiatedTypes)
        {
            switch (type.tag)
            {
            case TypeEnum.STRUCT:
                if (type.structDef.name == dummyType.typeName)
                {

                }
                break;
            default:
                break;
            }
        }
        return null;
    }

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
            return type;
        case TypeEnum.AGGREGATE:
            foreach (ref t; type.aggregate.templateInstantiations)
            {
                if (t.tag == TypeEnum.AGGREGATE
                    && t.aggregate.typeName in mappings)
                {
                    t = mappings[t.aggregate.typeName];
                }
            }
            "_instantiateTypeTemplate() AGGREGATE".writeln;
            ("  BEFORE: " ~ type.formatFull).writeln;

            //if (type.aggregate.typeName in records.structDefs)
            //{
            //    auto structDef = records.structDefs[type.aggregate.typeName]
            //                            .copy;
            //    if (type.aggregate.templateInstantiations.length
            //        != structDef.templateParams.length)
            //    {
            //        throw new Exception(
            //            "Template instantiation count mismatch."
            //        );
            //    }
            //    type.tag = TypeEnum.STRUCT;
            //    type.structDef = structDef;
            //    type = type.instantiateTypeTemplate(mappings, records);
            //}
            //else if (type.aggregate.typeName in records.variantDefs)
            //{
            //    auto variantDef = records.variantDefs[type.aggregate.typeName]
            //                             .copy;
            //    if (type.aggregate.templateInstantiations.length
            //        != variantDef.templateParams.length)
            //    {
            //        throw new Exception(
            //            "Template instantiation count mismatch."
            //        );
            //    }
            //    type.tag = TypeEnum.VARIANT;
            //    type.variantDef = variantDef;
            //    type = type.instantiateTypeTemplate(mappings, records);
            //}
            //else
            //{
            //    throw new Exception("Instantiation of non-existent type.");
            //}

            ("  AFTER : " ~ type.formatFull).writeln;
            return type.normalize(records);
        case TypeEnum.SET:
            if (type.set.setType.tag == TypeEnum.AGGREGATE
                && type.set.setType.aggregate.typeName in mappings)
            {
                type.set.setType
                    = mappings[type.set.setType.aggregate.typeName];
            }
            return type;
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
            return type;
        case TypeEnum.ARRAY:
            if (type.array.arrayType.tag == TypeEnum.AGGREGATE
                && type.array.arrayType.aggregate.typeName in mappings)
            {
                type.array.arrayType
                    = mappings[type.array.arrayType.aggregate.typeName];
            }
        case TypeEnum.CHAN:
            if (type.chan.chanType.tag == TypeEnum.AGGREGATE
                && type.chan.chanType.aggregate.typeName in mappings)
            {
                type.chan.chanType
                    = mappings[type.chan.chanType.aggregate.typeName];
            }
            return type;
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
            return type;
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
            return type;
        }
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
    case TypeEnum.SET:
    case TypeEnum.HASH:
    case TypeEnum.ARRAY:
    case TypeEnum.AGGREGATE:
    case TypeEnum.TUPLE:
    case TypeEnum.FUNCPTR:
        return type;
    case TypeEnum.CHAN:
        if (type.chan.chanType.tag == TypeEnum.AGGREGATE
            && type.chan.chanType.aggregate.typeName in mappings)
        {
            type.chan.chanType
                = mappings[type.chan.chanType.aggregate.typeName];
        }
        return type;
    case TypeEnum.VARIANT:
        type.variantDef.mappings = mappings;
        auto missing = mappings.keys
                               .setSymmetricDifference(type.variantDef
                                                           .templateParams);
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
        "start loop".writeln;
        foreach (ref member; type.variantDef.members)
        {
            "loop".writeln;
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
        "end loop".writeln;
        type.variantDef.instantiated = true;
        return type;
    case TypeEnum.STRUCT:
        type.structDef.mappings = mappings;
        auto missing = mappings.keys
                               .setSymmetricDifference(type.structDef
                                                           .templateParams);
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
        return type;
    }
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
