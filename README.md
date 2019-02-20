# CBOR.jl

[![Build Status](https://travis-ci.org/saurvs/CBOR.jl.svg?branch=master)](https://travis-ci.org/saurvs/CBOR.jl)
[![Build Status](https://ci.appveyor.com/api/projects/status/mudb34qrxjh9hud2?svg=true)](https://ci.appveyor.com/project/saurvs/cbor-jl)
[![](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/saurvs/jl/blob/master/LICENSE.md)

**CBOR.jl** is a Julia package for working with the **CBOR** data format,
providing straightforward encoding and decoding for Julia types.

## About CBOR
The **Concise Binary Object Representation** is a data format that's based upon
an extension of the JSON data model, whose stated design goals
include: small code size, small message size, and
extensibility without the need for version negotiation. The format is formally
defined in [RFC 7049](https://tools.ietf.org/html/rfc7049).

## Usage

Add the package

```julia
Pkg.add("CBOR")
```

and add the module

```julia
using CBOR
```

### Encoding and Decoding

Encoding and decoding follow the simple pattern

```julia
bytes = encode(data)

data = decode(bytes)
```

where `bytes` is of type `Array{UInt8, 1}`, and `data` returned from `decode()`
is *usually* of the same type that was passed into `encode()` but always
contains the original data.

#### Primitive Integers

All `Signed` and `Unsigned` types, *except* `Int128` and `UInt128`, are encoded
as CBOR `Type 0` or `Type 1`

```julia
> encode(21)
1-element Array{UInt8,1}: 0x15

> encode(-135713)
5-element Array{UInt8,1}: 0x3a 0x00 0x02 0x12 0x20

> bytes = encode(typemax(UInt64))
9-element Array{UInt8,1}: 0x1b 0xff 0xff 0xff 0xff 0xff 0xff 0xff 0xff

> decode(bytes)
18446744073709551615
```

#### Byte Strings

An `AbstractVector{UInt8}` is encoded as CBOR `Type 2`

```julia
> encode(UInt8[x*x for x in 1:10])
11-element Array{UInt8, 1}: 0x4a 0x01 0x04 0x09 0x10 0x19 0x24 0x31 0x40 0x51 0x64
```

#### Strings

`String` are encoded as CBOR `Type 3`

```julia
> encode("Valar morghulis")
16-element Array{UInt8,1}: 0x4f 0x56 0x61 0x6c 0x61 ... 0x68 0x75 0x6c 0x69 0x73

> bytes = encode("אתה יכול לקחת את סוס אל המים, אבל אתה לא יכול להוכיח שום דבר אמיתי")
119-element Array{UInt8,1}: 0x78 0x75 0xd7 0x90 0xd7 ... 0x99 0xd7 0xaa 0xd7 0x99

> decode(bytes)
"אתה יכול לקחת את סוס אל המים, אבל אתה לא יכול להוכיח שום דבר אמיתי"
```

#### Floats

`Float64`, `Float32` and `Float16` are encoded as CBOR `Type 7`

```julia
> encode(1.23456789e-300)
9-element Array{UInt8, 1}: 0xfb 0x01 0xaa 0x74 0xfe 0x1c 0x13 0x2c 0x0e

> bytes = encode(Float32(pi))
5-element Array{UInt8, 1}: 0xfa 0x40 0x49 0x0f 0xdb

> decode(bytes)
3.1415927f0
```

#### Arrays

`AbstractVector` and `Tuple` types, except of course `AbstractVector{UInt8}`,
are encoded as CBOR `Type 4`

```julia
> bytes = encode((-7, -8, -9))
4-element Array{UInt8, 1}: 0x83 0x26 0x27 0x28

> decode(bytes)
3-element Array{Any, 1}: -7 -8 -9

> bytes = encode(["Open", 1, 4, 9.0, "the pod bay doors hal"])
39-element Array{UInt8, 1}: 0x85 0x44 0x4f 0x70 0x65 ... 0x73 0x20 0x68 0x61 0x6c

> decode(bytes)
5-element Array{Any, 1}: "Open" 1 4 9.0 "the pod bay doors hal"

> bytes = encode([log2(x) for x in 1:10])
91-element Array{UInt8, 1}: 0x8a 0xfb 0x00 0x00 0x00 ... 0x4f 0x09 0x79 0xa3 0x71

> decode(bytes)
10-element Array{Any, 1}: 0.0 1.0 1.58496 2.0 2.32193 2.58496 2.80735 3.0 3.16993 3.32193
```

#### Maps

An `AbstractDict` type is encoded as CBOR `Type 5`

```julia
> d = Dict()
> d["GNU's"] = "not UNIX"
> d[Float64(e)] = [2, "+", 0.718281828459045]

> bytes = encode(d)
38-element Array{UInt8, 1}: 0xa2 0x65 0x47 0x4e 0x55 ... 0x28 0x6f 0x8a 0xd2 0x56

> decode(bytes)
Dict{Any,Any} with 2 entries:
  "GNU's"           => "not UNIX"
  2.718281828459045 => Any[0x02, "+", 0.718281828459045]
```

#### Tagging

To *tag* one of the above types, encode a `Pair` with `first` being an
**non-negative** integer, and `second` being the data you want to tag.

```julia
> bytes = encode(Pair(80, "web servers"))

> data = decode(bytes)
0x50=>"HTTP Web Server"
```

There exists an [IANA registery](http://www.iana.org/assignments/cbor-tags/cbor-tags.xhtml)
which assigns certain meanings to tags; for example, a string tagged
with a value of `32` is to be interpreted as a
[Uniform Resource Locater](https://tools.ietf.org/html/rfc3986). To decode a
tagged CBOR data item, and then to automatically interpret the meaning of the
tag, use `decode_with_iana`.

For example, a Julia `BigInt` type is encoded as an `Array{UInt8, 1}` containing
the bytes of it's hexadecimal representation, and tagged with a value of `2` or
`3`

```julia
> b = BigInt(factorial(20))
2432902008176640000

> bytes = encode(b * b * -b)
34-element Array{UInt8,1}: 0xc3 0x58 0x1f 0x13 0xd4 ... 0xff 0xff 0xff 0xff 0xff
```

To decode `bytes` *without* interpreting the meaning of the tag, use `decode`

```julia
> decode(bytes)
0x03 => UInt8[0x96, 0x58, 0xd1, 0x85, 0xdb .. 0xff 0xff 0xff 0xff 0xff]
```
To decode `bytes` and to interpret the meaning of the tag, use
`decode_with_iana`

```julia
> decode_with_iana(bytes)
-14400376622525549608547603031202889616850944000000000000
```

Currently, only `BigInt` is supported for automatically tagged encoding and
decoding; more Julia types will be added in the future.

#### Composite Types

A generic `DataType` that isn't one of the above types is encoded through
`encode` using reflection. This is supported only if all of the fields of the
type belong to one of the above types.

For example, say you have a user-defined type `Point`

```julia
type Point
    x::Int64
    y::Float64
    space::String
end

point = Point(1, 3.4, "Euclidean")
```

When `point` is passed into `encode`, it is first converted to a `Dict`
containing the symbolic names of it's fields as keys associated to their
respective values and a `"type"` key associated to the type's
symbolic name, like so

```julia
Dict{Any, Any} with 3 entries:
  "x"     => 0x01
  "type"  => "Point"
  "y"     => 3.4
  "space" => "Euclidean"
```

The `Dict` is then encoded as CBOR `Type 5`.

#### Indefinite length collections

To encode collections of *indefinite* length, first create a *producer*
function

```julia
function producer(ch::Channel)
    for i in 1:10
        put!(ch,i*i)
    end
end
```

Wrap it in a `Channel`

```julia
task = Channel(producer)
```

Encode a `Pair` with `first` being the `Channel` just created, and `second` being
a valid collection type you want to encode.

```julia
> encode(Pair(task, AbstractVector))
18-element Array{UInt8, 1}: 0x9f 0x01 0x04 0x09 0x10 ... 0x18 0x51 0x18 0x64 0xff

> decode(bytes)
10-element Array{Any, 1}: 1 4 9 16 25 36 49 64 81 100
```

While encoding an indefinite length `Map`, produce first the key and then the
value for each key-value pair.

```julia
function cubes(ch::Channel)
    for i in 1:10
        put!(ch,i)       # key
        put!(ch,i*i*i)   # value
    end
end

> bytes = encode(Pair(Channel(cubes), AbstractDict))
34-element Array{UInt8, 1}: 0xbf 0x01 0x01 0x02 0x08 ... 0x0a 0x19 0x03 0xe8 0xff

> decode(bytes)
Dict{Any, Any} with 10 entries:
  0x07 => 0x0157
  0x04 => 0x40
  0x09 => 0x02d9
  0x0a => 0x03e8
  0x02 => 0x08
  0x03 => 0x1b
  0x05 => 0x7d
  0x08 => 0x0200
  0x06 => 0xd8
  0x01 => 0x01s
```

Note that when an indefinite length CBOR `Type 2` or `Type 3` is decoded,
the result is a *concatenation* of the individual elements.

```julia
function producer(ch::Channel)
    for c in ["F", "ire", " ", "and", " ", "Blo", "od"]
        put!(ch,c)
    end
end

> bytes = encode(Pair(Channel(producer), String))
23-element Array{UInt8, 1}: 0x7f 0x61 0x46 0x63 0x69 ... 0x6f 0x62 0x6f 0x64 0xff

> decode(bytes)
"Fire and Blood"
```

### Caveats

While encoding a `Float16` is supported, decoding one isn't.

Encoding a `UInt128` and an `Int128` isn't supported; use a `BigInt` instead.

The CBOR array type is always decoded as a `Vector`.

The CBOR map type is always decoded as a `Dict`.

Decoding CBOR data that isn't well-formed is unpredictable.
