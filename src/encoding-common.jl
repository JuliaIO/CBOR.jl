#=
Copyright (c) 2016 Saurav Sachidanand

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
=#

cbor_tag(::UInt8) = ADDNTL_INFO_UINT8
cbor_tag(::UInt16) = ADDNTL_INFO_UINT16
cbor_tag(::UInt32) = ADDNTL_INFO_UINT32
cbor_tag(::UInt64) = ADDNTL_INFO_UINT64

cbor_tag(::Float64) = ADDNTL_INFO_FLOAT64
cbor_tag(::Float32) = ADDNTL_INFO_FLOAT32
cbor_tag(::Float16) = ADDNTL_INFO_FLOAT16

function encode_unsigned_with_type(
        io::IO, typ::UInt8, num::Unsigned
    )
    write(io, typ | cbor_tag(num))
    write(io, bswap(num))
end


function encode_type_number(io::IO, typ::UInt8, x)
    encode_type_number(io, typ, length(x))
end

"""
Array lengths and other integers (e.g. tags) in CBOR are encoded with smallest integer type,
which we do with this method!
"""
function encode_type_number(io::IO, typ::UInt8, num::Integer)
    @assert num >= 0 "array lengths must be greater 0. Found: $num"
    if num < SINGLE_BYTE_UINT_PLUS_ONE
        write(io, typ | UInt8(num)) # smaller 24 gets directly stored in type tag
    elseif num < UINT8_MAX_PLUS_ONE
        encode_unsigned_with_type(io, typ, UInt8(num))
    elseif num < UINT16_MAX_PLUS_ONE
        encode_unsigned_with_type(io, typ, UInt16(num))
    elseif num < UINT32_MAX_PLUS_ONE
        encode_unsigned_with_type(io, typ, UInt32(num))
    elseif num < UINT64_MAX_PLUS_ONE
        encode_unsigned_with_type(io, typ, UInt64(num))
    else
        error("128-bits ints can't be encoded in the CBOR format.")
    end
end


function encode(io::IO, float::Union{Float64, Float32, Float16})
    write(io, TYPE_7 | cbor_tag(float))
    # hton only works for 32 + 64, while bswap works for all
    write(io, Base.bswap_int(float))
end


# ------- straightforward encoding for a few Julia types
function encode(io::IO, bool::Bool)
    write(io, CBOR_FALSE_BYTE + bool)
end

function encode(io::IO, num::Unsigned)
    encode_unsigned_with_type(io, TYPE_0, num)
end

function encode(io::IO, num::T) where T <: Signed
    encode_unsigned_with_type(io, TYPE_1, unsigned(-num - one(T)))
end

function encode(io::IO, byte_string::Vector{UInt8})
    encode_type_number(io, TYPE_2, byte_string)
    write(io, byte_string)
end

function encode(io::IO, string::String)
    encode_type_number(io, TYPE_3, sizeof(string))
    write(io, string)
end

function encode(io::IO, list::Vector)
    encode_type_number(io, TYPE_4, list)
    for e in list
        encode(io, e)
    end
end

function encode(io::IO, map::Dict)
    encode_type_number(io, TYPE_5, map)
    for (key, value) in map
        encode(io, key)
        encode(io, value)
    end
end

function encode(io::IO, big_int::BigInt)
    tag = if big_int < 0
        big_int = -big_int - 1
        NEG_BIG_INT_TAG
    else
        POS_BIG_INT_TAG
    end
    hex_str = hex(big_int)
    if isodd(length(hex_str))
        hex_str = "0" * hex_str
    end
    encode(io, Tag(tag, hex2bytes(hex_str)))
end

function encode(io::IO, tag::Tag)
    if typeof(tag.id) <: Integer && tag.id >= 0
        encode_with_tag(io, Unsigned(tag.id), tag.data)
    else # typeof(tag.id) <: Channel Must be Channel, since it's Union{Int, Channel}
        encode_indef_length_collection(io, tag.id, tag.data)
    end
end


# ------- encoding for indefinite length collections
function encode_indef_length_collection(
        io::IO, producer::Channel, collection_type
    )
    if collection_type <: AbstractVector{UInt8}
        typ = TYPE_2
    elseif collection_type <: String
        typ = TYPE_3
    elseif collection_type <: Union{AbstractVector, Tuple}
        typ = TYPE_4
    elseif collection_type <: AbstractDict
        typ = TYPE_5
    else
        error(@sprintf "Collection type %s is not supported for indefinite length encoding." collection_type)
    end

    write(io, typ | ADDNTL_INFO_INDEF)

    count = 0
    for e in producer
        encode(io, e)
        count += 1
    end

    if typ == TYPE_5 && isodd(count)
        error(@sprintf "Collection type %s requires an even number of input data items in order to be consistent." collection_type)
    end
    write(io, BREAK_INDEF)
end

# ------- encoding with tags

function encode_with_tag(io::IO, tag::Unsigned, data)
    encode_type_number(io, TYPE_6, tag)
    encode(io, data)
end


struct Undefined
end

function encode(io::IO, null::Nothing)
    write(io, CBOR_NULL_BYTE)
end

function encode(io::IO, undef::Undefined)
    write(io, CBOR_UNDEF_BYTE)
end


function fields2array(typ::T) where T
    fnames = fieldnames(T)
    getfield.((typ,), [fnames...])
end

"""
Any Julia type get's serialized as Tag 27
Tag             27
Data Item       array [typename, constructargs...]
Semantics       Serialised language-independent object with type name and constructor arguments
Reference       http://cbor.schmorp.de/generic-object
Contact         Marc A. Lehmann <cbor@schmorp.de>
"""
function encode(io::IO, struct_type::T) where T
    tio = IOBuffer();
    print(tio, "Julia/") # language name tag like in the specs
    # encode the type in the tag
    io64 = Base64EncodePipe(tio); serialize(io64, T); close(io64)
    # TODO don't use a Dict and use  [typename, constructargs...] as indicated
    # by the specs... The thing is, Closure expects a 2 length array -.-
    encode(
        io,
        Tag(
            CUSTOM_LANGUAGE_TYPE,
            [String(take!(tio)), fields2array(struct_type)]
        )
    )
end
