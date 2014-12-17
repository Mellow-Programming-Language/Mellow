import std.stdio;
import parser;
import Record;
import typedecl;
import std.range;

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
        structDef.instantiate(mappings);
        type.tag = TypeEnum.STRUCT;
        type.structDef = structDef;
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
        variantDef.instantiate(mappings);
        type.tag = TypeEnum.VARIANT;
        type.variantDef = variantDef;
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
    auto type = new Type();
    type.tag = TypeEnum.STRUCT;
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
                throw new Exception("Cannot normalize struct def");
            }
        }
    }
    type.structDef = structCopy;
    return type;
}

Type* normalizeVariantDefs(RecordBuilder records, VariantType* variantType)
{
    auto variantCopy = variantType.copy;
    auto type = new Type();
    type.tag = TypeEnum.VARIANT;
    foreach (ref member; variantCopy.members)
    {
        foreach (ref elemType; member.constructorElems.tuple.types)
        {
            if (elemType.tag == TypeEnum.AGGREGATE)
            {
                if (elemType.aggregate.typeName in records.structDefs)
                {
                    auto instance = new Type();
                    instance.tag = TypeEnum.STRUCT;
                    instance.structDef =
                        records.structDefs[elemType.aggregate.typeName].copy;
                    elemType = instance;
                }
                else if (elemType.aggregate.typeName in records.variantDefs)
                {
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
    type.variantDef = variantCopy;
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
