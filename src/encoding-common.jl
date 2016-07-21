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

function encode_unsigned_with_type(type_bits::UInt8, num::Unsigned)
    if num < SINGLE_BYTE_UINT_PLUS_ONE
        return UInt8[type_bits | num]
    elseif num < UINT8_MAX_PLUS_ONE
        return UInt8[type_bits | ADDNTL_INFO_UINT8, num]
    end

    cbor_bytes = UInt8[]
    if num < UINT16_MAX_PLUS_ONE
        push!(cbor_bytes, type_bits | ADDNTL_INFO_UINT16)
        byte_len = sizeof(UInt16)
    elseif num < UINT32_MAX_PLUS_ONE
        push!(cbor_bytes, type_bits | ADDNTL_INFO_UINT32)
        byte_len = sizeof(UInt32)
    elseif num < UINT64_MAX_PLUS_ONE
        push!(cbor_bytes, type_bits | ADDNTL_INFO_UINT64)
        byte_len = sizeof(UInt64)
    else
        error(
            "Encoding of an integer stored as a primitive of size greater " *
            "than 64-bits is not supported. Use a BigInt instead.")
    end

    for _ in 1:byte_len
        if num > 0
            insert!(cbor_bytes, 2, num & LOWEST_ORDER_BYTE_MASK)
            num >>>= BITS_PER_BYTE
        else
            insert!(cbor_bytes, 2, zero(UInt8))
        end
    end

    return cbor_bytes
end
