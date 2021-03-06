#--
# the hayago scripting language
# copyright (C) iLiquid, 2019-2020
# licensed under the MIT license
#--

import strutils

const
  ValueSize* = max([
    sizeof(bool),
    sizeof(float),
    sizeof(string)
  ])

const
  tyNil* = 0
  tyBool* = 1
  tyInt* = 2
  tyFloat* = 3
  tyString* = 4
  tyFirstObject* = 10

type
  TypeId* = range[0..32766]  # max amount of case object branches

  Object* = ref object
    ## A hayago object.
    case isForeign: bool
    of true: data*: pointer
    of false: fields*: seq[Value]

  Value* = object
    ## A hayago value.
    case typeId*: TypeId  ## the type ID, used for dynamic dispatch
    of tyBool: boolVal*: bool
    of tyInt: intVal*: int64
    of tyFloat: floatVal*: float64
    of tyString: stringVal*: ref string
    else: objectVal*: Object

  Stack* = seq[Value]
    ## A runtime stack of values, used in the VM.
  StackView* = ptr UncheckedArray[Value]
    ## An unsafe view into a Stack.

  ForeignProc* = proc (args: StackView): Value
    ## A foreign proc.

proc `$`*(value: Value): string =
  ## Returns a value's string representation.
  result =
    case value.typeId
    of tyNil: "nil"
    of tyBool: $value.boolVal
    of tyInt: $value.intVal
    of tyFloat: $value.floatVal
    of tyString: escape($value.stringVal[])
    else: "<object>"

proc initValue*(value: bool): Value =
  ## Initializes a bool value.
  result = Value(typeId: tyBool, boolVal: value)

proc initValue*(value: int64): Value =
  ## Initializes a float value.
  result = Value(typeId: tyInt, intVal: value)

proc initValue*(value: float64): Value =
  ## Initializes a float value.
  result = Value(typeId: tyFloat, floatVal: value)

proc initValue*(value: string): Value =
  ## Initializes a string value.
  result = Value(typeId: tyString)
  new(result.stringVal)
  result.stringVal[] = value

proc initValue*[T: tuple | object | ref](id: TypeId, value: T): Value =
  ## Safely initializes a foreign object value.
  ## This copies the value onto the heap for ordinary objects and tuples,
  ## and GC_refs the value for refs. The finalizer for objectVal deallocates or
  ## GC_unrefs the foreign data to maintain memory safety.
  result = Value(typeId: id)
  when T is tuple | object:
    new(result.objectVal) do (obj: Object):
      dealloc(obj.data)
    result.objectVal.isForeign = true
    let data = cast[ptr T](alloc(sizeof(T)))
    data[] = value
    result.objectVal.data = data
  elif T is ref:
    new(result.objectVal) do (obj: Object):
      GC_unref(cast[ref T](obj.data))
    result.objectVal.isForeign = true
    GC_ref(value)
    result.objectVal.data = cast[pointer](value)

proc foreign*(value: var Value, T: typedesc): T =
  result = cast[var T](value.objectVal.data)

proc foreign*(value: Value, T: typedesc): T =
  ## Get an object value. This is a *mostly* safe operation, but attempting to
  ## get a foreign type different from the value's is undefined behavior.
  result = cast[ptr T](value.objectVal.data)[]

const nilObject* = -1 ## The field count used for initializing a nil object.

proc initObject*(id: TypeId, fieldCount: int): Value =
  ## Initializes a native object value, with ``fieldCount`` fields.
  result = Value(typeId: id)
  if fieldCount == nilObject:
    result.objectVal = nil
  else:
    result.objectVal = Object(isForeign: false,
                              fields: newSeq[Value](fieldCount))

