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

function encode_unsigned_with_type(type_bits::UInt8,
                                   num::Unsigned,
                                   bytes::Array{UInt8, 1})
    if num < SINGLE_BYTE_UINT_PLUS_ONE
        byte_len = 0
        addntl_info = num
    elseif num < UINT8_MAX_PLUS_ONE
        byte_len = sizeof(UInt8)
        addntl_info = ADDNTL_INFO_UINT8
    elseif num < UINT16_MAX_PLUS_ONE
        byte_len = sizeof(UInt16)
        addntl_info = ADDNTL_INFO_UINT16
    elseif num < UINT32_MAX_PLUS_ONE
        byte_len = sizeof(UInt32)
        addntl_info = ADDNTL_INFO_UINT32
    elseif num < UINT64_MAX_PLUS_ONE
        byte_len = sizeof(UInt64)
        addntl_info = ADDNTL_INFO_UINT64
    else
        error("128-bits ints can't be encoded in the CBOR format.")
    end

    push!(bytes, type_bits | addntl_info)

    i = length(bytes) + 1
    for _ in 1:byte_len
        insert!(bytes, i, num & LOWEST_ORDER_BYTE_MASK)
        num >>>= BITS_PER_BYTE
    end
end

# ------- straightforward encoding for a few Julia types

function encode(bool::Bool, bytes::Array{UInt8, 1})
    push!(bytes, CBOR_FALSE_BYTE + bool)
end

function encode(num::Unsigned, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_0, num, bytes)
end

function encode(num::Signed, bytes::Array{UInt8, 1})
    if num < 0
        return encode_unsigned_with_type(TYPE_1, Unsigned(-num - 1), bytes)
    else
        return encode_unsigned_with_type(TYPE_0, Unsigned(num), bytes)
    end
end

function encode(byte_string::AbstractVector{UInt8}, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_2, Unsigned(length(byte_string)), bytes)
    append!(bytes, byte_string)
end

function encode(string::String, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_3, Unsigned(sizeof(string)), bytes)
    append!(bytes, Vector{UInt8}(string))
end

function encode(list::Union{AbstractVector, Tuple}, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_4, Unsigned(length(list)), bytes)
    for e in list
        encode(e, bytes)
    end
end

function encode(map::AbstractDict, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_5, Unsigned(length(map)), bytes)
    for (key, value) in map
        encode(key, bytes)
        encode(value, bytes)
    end
end

function encode(big_int::BigInt, bytes::Array{UInt8, 1})
    if big_int < 0
        hex_str = hex(-big_int - 1)
        tag = NEG_BIG_INT_TAG
    else
        hex_str = hex(big_int)
        tag = POS_BIG_INT_TAG
    end

    encode_unsigned_with_type(TYPE_6, Unsigned(tag), bytes)

    if isodd(length(hex_str))
        hex_str = "0" * hex_str
    end

    encode(hex2bytes(hex_str), bytes)
end

cbor_tag(x::Float64) = TYPE_7 | ADDNTL_INFO_FLOAT64
cbor_tag(x::Float32) = TYPE_7 | ADDNTL_INFO_FLOAT32
cbor_tag(x::Float16) = TYPE_7 | ADDNTL_INFO_FLOAT16


function encode(io::IO, float::Union{Float64, Float32, Float16})
    write(io, cbor_tag(float))
    # hton only works for 32 + 64, while bswap works for all
    write(io, Base.bswap_int(float))
end


function encode(pair::Pair, bytes::Array{UInt8, 1})
    if typeof(pair.first) <: Integer && pair.first >= 0
        encode_with_tag(Unsigned(pair.first), pair.second, bytes)
    elseif typeof(pair.first) <: Channel
        encode_indef_length_collection(pair.first, pair.second, bytes)
    else
        encode_custom_type(pair, bytes)
    end
end

function encode(data, bytes::Array{UInt8, 1})
    encode_custom_type(data, bytes)
end

# ------- encoding for indefinite length collections

function encode_indef_length_collection(producer::Channel, collection_type,
                                        bytes::Array{UInt8, 1})
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

    push!(bytes, typ | ADDNTL_INFO_INDEF)

    count = 0
    for e in producer
        encode(e, bytes)
        count += 1
    end

    if typ == TYPE_5 && isodd(count)
        error(@sprintf "Collection type %s requires an even number of input data items in order to be consistent." collection_type)
    end

    push!(bytes, BREAK_INDEF)
end

# ------- encoding with tags

function encode_with_tag(tag::Unsigned, data, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_6, tag, bytes)
    encode(data, bytes)
end

# ------- encoding for user-defined types


function encode_custom_type(data, bytes::Array{UInt8, 1})
    type_map = Dict()

    type_map[String("type")] = String(string(typeof(data)) )

    for f in fieldnames(data)
        type_map[String(string(f))] = data.(f)
    end

    encode(type_map, bytes)
end


# ------- encoding for Simple types

struct Simple
    val::UInt8
end

Base.isequal(a::Simple, b::Simple) = Base.isequal(a.val, b.val)

function encode(simple::Simple, bytes::Array{UInt8, 1})
    encode_unsigned_with_type(TYPE_7, simple.val, bytes)
end

# ------- encoding for Null and Undefined

struct Null
end

struct Undefined
end

function encode(null::Null, bytes::Array{UInt8, 1})
    push!(bytes, CBOR_NULL_BYTE)
end

function encode(undef::Undefined, bytes::Array{UInt8, 1})
    push!(bytes, CBOR_UNDEF_BYTE)
end
