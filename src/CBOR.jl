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

module CBOR

include("consts.jl")
include("encoder.jl")
include("decoder.jl")

# ------- straightforward decoding for usual Julia types

function decode(cbor_bytes::Array{UInt8, 1})
    data, _ = decode_next(1, cbor_bytes)
    return data
end

# ------- straightforward encoding for usual Julia types

function encode(bool::Bool)
    return UInt8[CBOR_FALSE_BYTE + bool]
end

function encode(num::Unsigned)
    encode_unsigned_with_type(TYPE_0, num)
end

function encode(num::Signed)
    if num < 0
        return encode_unsigned_with_type(TYPE_1, Unsigned(-num - 1) )
    else
        return encode_unsigned_with_type(TYPE_0, Unsigned(num))
    end
end

function encode(ascii_str::ASCIIString)
    return encode(ascii_str.data)
end

function encode(bytes::Array{UInt8, 1})
    cbor_bytes = encode_unsigned_with_type(TYPE_2, Unsigned(length(bytes)) )
    append!(cbor_bytes, bytes)
    return cbor_bytes
end

function encode(utf8_str::UTF8String)
    cbor_bytes = encode_unsigned_with_type(TYPE_3, Unsigned(sizeof(utf8_str)) )
    append!(cbor_bytes, utf8_str.data)
    return cbor_bytes
end

function encode(list::Union{AbstractVector,Tuple})
    cbor_bytes = encode_unsigned_with_type(TYPE_4, Unsigned(length(list)) )
    for e in list
        append!(cbor_bytes, encode(e))
    end
    return cbor_bytes
end

function encode(map::Associative)
    cbor_bytes = encode_unsigned_with_type(TYPE_5, Unsigned(length(map)) )
    for (key, value) in map
        append!(cbor_bytes, encode(key))
        append!(cbor_bytes, encode(value))
    end
    return cbor_bytes
end

function encode(big_int::BigInt)
    hex_str, tag =
        if big_int < 0
            hex(-big_int - 1), NEG_BIG_INT_TAG
        else
            hex(big_int), POS_BIG_INT_TAG
        end

    cbor_bytes = encode_unsigned_with_type(TYPE_6, Unsigned(tag))

    if isodd(length(hex_str))
        hex_str = "0" * hex_str
    end
    append!(cbor_bytes, encode(hex2bytes(hex_str)) )

    return cbor_bytes
end

function encode(float::AbstractFloat)
    cbor_bytes = hex2bytes(num2hex(float))
    cbor_bytes_len = length(cbor_bytes)

    if cbor_bytes_len == SIZE_OF_FLOAT64
        unshift!(cbor_bytes, TYPE_7 | ADDNTL_INFO_FLOAT64)
    elseif cbor_bytes_len == SIZE_OF_FLOAT32
        unshift!(cbor_bytes, TYPE_7 | ADDNTL_INFO_FLOAT32)
    else cbor_bytes_len == SIZE_OF_FLOAT16
        unshift!(cbor_bytes, TYPE_7 | ADDNTL_INFO_FLOAT16)
        warn("Decoding of 16-bit float is not supported.")
    end

    return cbor_bytes
end

end
