import std.stdio;
import parser;
import Record;
import typedecl;
import std.range;

Type* instantiateAggregate(RecordBuilder records, AggregateType* aggregate)
{
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
        auto type = new Type();
        type.tag = TypeEnum.STRUCT;
        type.structDef = structDef;
        return type;
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
        auto type = new Type();
        type.tag = TypeEnum.VARIANT;
        type.variantDef = variantDef;
        return type;
    }
    else
    {
        throw new Exception("Instantiation of non-existent type.");
    }
}
