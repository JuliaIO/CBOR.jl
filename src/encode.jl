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

function encode_length(io::IO, typ::UInt8, x)
    encode_smallest_int(io, typ, x isa String ? sizeof(x) : length(x))
end

"""
Array lengths and other integers (e.g. tags) in CBOR are encoded with smallest integer type,
which we do with this method!
"""
function encode_smallest_int(io::IO, typ::UInt8, num::Integer)
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
    encode_length(io, TYPE_2, byte_string)
    write(io, byte_string)
end

function encode(io::IO, string::String)
    encode_length(io, TYPE_3, string)
    write(io, string)
end

function encode(io::IO, list::Vector)
    encode_length(io, TYPE_4, list)
    for e in list
        encode(io, e)
    end
end

function encode(io::IO, map::Dict)
    encode_length(io, TYPE_5, map)
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
    tag.id >= 0 || error("Tag needs to be a positive integer")
    encode_with_tag(io, Unsigned(tag.id), tag.data)
end

"""
Wrapper for collections with undefined length, that will then get encoded
in the cbor format. Underlying is just
"""
struct UndefLength{ET, A}
    iter::A
end

function UndefLength(iter::T) where T
    UndefLength{eltype(iter), T}(iter)
end

function UndefLength{T}(iter::A) where {T, A}
    UndefLength{T, A}(iter)
end

Base.iterate(x::UndefLength) = iterate(x.iter)
Base.iterate(x::UndefLength, state) = iterate(x.iter, state)

# ------- encoding for indefinite length collections
function encode(
        io::IO, iter::UndefLength{ET}
    ) where ET
    if ET in (Vector{UInt8}, String)
        typ = ET == Vector{UInt8} ? TYPE_2 : TYPE_3
        write(io, typ | ADDNTL_INFO_INDEF)
        foreach(x-> encode(io, x), iter)
    else
        typ = ET <: Pair ? TYPE_5 : TYPE_4 # Dict or any array
        write(io, typ | ADDNTL_INFO_INDEF)
        for e in iter
            if e isa Pair
                encode(io, e[1])
                encode(io, e[2])
            else
                encode(io, e)
            end
        end
    end
    write(io, BREAK_INDEF)
end

# ------- encoding with tags

function encode_with_tag(io::IO, tag::Unsigned, data)
    encode_smallest_int(io, TYPE_6, tag)
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

struct SmallInteger{T}
    num::T
end
Base.convert(::Type{<: SmallInteger}, x) = SmallInteger(x)
Base.convert(::Type{<: SmallInteger}, x::SmallInteger) = x
Base.:(==)(a::SmallInteger, b::SmallInteger) = a.num == b.num
Base.:(==)(a::Number, b::SmallInteger) = a == b.num
Base.:(==)(a::SmallInteger, b::Number) = a.num == b

function encode(io::IO, small::SmallInteger{<: Unsigned})
    encode_smallest_int(io, TYPE_0, small.num)
end
function encode(io::IO, small::SmallInteger{<: Signed})
    if small.num >= 0
        encode_smallest_int(io, TYPE_0, unsigned(small.num))
    else
        encode_smallest_int(io, TYPE_1, unsigned(-small.num - one(small.num)))
    end
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
    # TODO don't use Serialization for the whole struct!
    # It almost works to deserialize from just the fields and type,
    # but that ends up being problematic for
    # anonymous functions (the type changes between serialization & deserialization)
    tio = IOBuffer(); serialize(tio, struct_type)
    encode(
        io,
        Tag(
            CUSTOM_LANGUAGE_TYPE,
            [string("Julia/", T), take!(tio), fields2array(struct_type)]
        )
    )
end
