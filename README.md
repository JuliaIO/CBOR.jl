# CBOR.jl [![Build Status](https://travis-ci.org/saurvs/CBOR.jl.svg?branch=master)](https://travis-ci.org/saurvs/CBOR.jl)

**CBOR.jl** is a Julia package for working with the **CBOR** data format. It
provides straightforward APIs for encoding and decoding.

## About CBOR
The Concise Binary Object Representation is a *binary* data format that is
based upon an extension of the JSON data model. It's stated design goals
include: an extremely small code size, fairly small message size, and
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

### The Encoding and Decoding API

Encoding and decoding follow the simple pattern

```julia
bytes = CBOR.encode(data)

data = CBOR.decode(bytes)
```

where `bytes` is of type `Array{UInt8, 1}`, and `data` is *usually* of the same
type passed into `encode()` but always contains the original data.

#### Primitive Integers

All `Signed` and `Unsigned` types, *except* `Int128` and `UInt128`, are encoded
as CBOR `Type 0` or `Type 1`

```julia
> CBOR.encode(21)
1-element Array{UInt8,1}: 0x15

> CBOR.encode(-135713)
5-element Array{UInt8,1}: 0x3a 0x00 0x02 0x12 0x20


> bytes = CBOR.encode(typemax(UInt64))
9-element Array{UInt8,1}: 0x1b 0xff 0xff 0xff 0xff 0xff 0xff 0xff 0xff

> CBOR.decode(bytes)
18446744073709551615
```

#### Byte Strings

`Array{UInt8, 1}` and `ASCIIString` types are encoded as CBOR `Type 2`

```julia
> CBOR.encode("Valar morghulis")
16-element Array{UInt8,1}: 0x4f 0x56 0x61 0x6c 0x61 ... 0x68 0x75 0x6c 0x69 0x73
```

#### UTF8 Strings

A `UTF8String` is encoded as CBOR `Type 3`

```julia
> bytes = CBOR.encode("אתה יכול לקחת את סוס אל המים, אבל אתה לא יכול להוכיח שום דבר אמיתי")
119-element Array{UInt8,1}: 0x78 0x75 0xd7 0x90 0xd7 ... 0x99 0xd7 0xaa 0xd7 0x99

> CBOR.decode(bytes)
"אתה יכול לקחת את סוס אל המים, אבל אתה לא יכול להוכיח שום דבר אמיתי"
```

#### Arrays

All `AbstractVector` and `Tuple` types are encoded as CBOR `Type 4`

#### Maps

An `Associative` type is encoded as CBOR `Type 5`

#### Floats

`Float64`, `Float32` and `Float16` are encoded as CBOR `Type 7`

```julia
> CBOR.encode(1.23456789e-300)
9-element Array{UInt8,1}: 0xfb 0x01 0xaa 0x74 0xfe 0x1c 0x13 0x2c 0x0e


> bytes = CBOR.encode(Float64(pi))
9-element Array{UInt8,1}: 0xfb 0x40 0x09 0x21 0xfb 0x54 0x44 0x2d 0x18

> CBOR.decode(bytes)
3.141592653589793
```

#### BigInts

A `BigInt` type is encoded as an `Array{UInt8, 1}` containing the bytes of the
hexadecimal form of it's numerical value, and tagged with a value of `2` or `3`

```julia
> b = BigInt(factorial(20)); b *= b
5919012181389927685417441689600000000

> bytes = CBOR.encode(b * -b)
34-element Array{UInt8,1}: 0xc3 0x58 0x1f 0x13 0xd4 ... 0xff 0xff 0xff 0xff 0xff

> CBOR.decode(bytes)
-35034705203442350200541990461054245403670690716216102748160000000000000000
```

#### User-defined types

A user-defined type is encoded through `encode` using reflection *only* if all
of it's fields are any of the above types.

```julia
type Point
    x::Int64
    y::Float64
end
```

When `Point` is passed into `encode`, it is first converted to a `Dict`
containing the symbolic names of it's fields as keys associated to their
respective values and a `"type"` key associated to the type's
symbolic name, like so

```julia
Dict{Any,Any} with 3 entries:
  "x"    => 0x01
  "type" => "Point"
  "y"    => 2.3
```

The `Dict` is then encoded as CBOR `Type 5`.

#### Tagging

To *tag* one of the above types, first wrap the tag *value* in a `CBOR.Tag`
type, and pass the it and value to be tagged to `encode(tag::Tag, data)`

#### Indefinite length collections

To encode collections of *indefinite* length, first create a producer function

### Caveats

While encoding a `Float16` is supported, decoding one isn't.

Encoding `UInt128` and `Int128` isn't supported; pass a `BigInt` instead.

The CBOR array type is always decoded as a `Vector`.

The CBOR map type is always decoded as a `Dict`.

Data tagged with values that are assigned a meaning in the *IANA* registery are
automatically interpreted and converted to appropriate Julia types whenever
possible.
