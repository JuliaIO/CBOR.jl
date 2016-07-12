module CBOR

const TYPE_0 = zero(UInt8)
const TYPE_1 = one(UInt8) << 5
const TYPE_2 = UInt8(2) << 5
const TYPE_3 = UInt8(3) << 5
const TYPE_4 = UInt8(4) << 5
const TYPE_5 = UInt8(5) << 5
const TYPE_6 = UInt8(6) << 5
const TYPE_7 = UInt8(7) << 5

function encode(bool::Bool)
    return UInt8[0xf4 + bool]
end

function encode_unsigned_with_type(type_bits::UInt8, num::Unsigned)
    if num < 0x18 # 0 to 23
        return UInt8[type_bits | num]
    elseif num < 0x100 # 8 bit unsigned integer
        return UInt8[type_bits | 24, num]
    end

    cbor_bytes = UInt8[]
    if num < 0x10000 # 16 bit unsigned integer
        push!(cbor_bytes, type_bits | 25)
        byte_len = 2
    elseif num < 0x100000000 # 32 bit unsigned integer
        push!(cbor_bytes, type_bits | 26)
        byte_len = 4
    else # 64 bit unsigned integer
        push!(cbor_bytes, type_bits | 27)
        byte_len = 8
    end

    for _ in 1:byte_len
        if num > 0
            insert!(cbor_bytes, 2, num & 0xFF)
            num = num >>> 8
        else
            insert!(cbor_bytes, 2, zero(UInt8))
        end
    end

    return cbor_bytes
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

function encode(byte_str::ASCIIString)
    cbor_bytes = encode_unsigned_with_type(TYPE_2, Unsigned(length(byte_str)) )
    for c in byte_str
        push!(cbor_bytes, UInt8(c))
    end
    return cbor_bytes
end

function encode(utf8_str::UTF8String)
    cbor_bytes = encode_unsigned_with_type(TYPE_3, Unsigned(sizeof(utf8_str)) )
    for c in utf8_str.data
        push!(cbor_bytes, UInt8(c))
    end
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

function encode(float::AbstractFloat)
    cbor_bytes = hex2bytes(num2hex(float))

    cbor_bytes_len = length(cbor_bytes)
    if cbor_bytes_len == 8 # IEEE 754 Double-Precision Float
        unshift!(cbor_bytes, TYPE_7 | UInt8(27))
    elseif cbor_bytes_len == 4 # IEEE 754 Single-Precision Float
        unshift!(cbor_bytes, TYPE_7 | UInt8(26))
    else cbor_bytes_len == 2 # IEEE 754 Half-Precision Float
        unshift!(cbor_bytes, TYPE_7 | UInt8(25))
    end

    return cbor_bytes
end

function encode(data)
    cbor_bytes = UInt8[]
    return cbor_bytes
end

function decode_unsigned(start_idx, unsigned_bytes::Array{UInt8, 1})
    addntl_info = unsigned_bytes[start_idx] & 0b0001_1111

    if addntl_info < 24 # 0-23
        return addntl_info, sizeof(UInt8)
    end

    data, byte_len =
        if addntl_info == 24
            zero(UInt8), sizeof(UInt8)
        elseif addntl_info == 25
            zero(UInt16), sizeof(UInt16)
        elseif addntl_info == 26
            zero(UInt32), sizeof(UInt32)
        elseif addntl_info == 27
            zero(UInt64), sizeof(UInt64)
        end

    byte_len += 1
    start_idx -= 1
    for i in 2:byte_len
        data <<= 8
        data |= unsigned_bytes[start_idx + i]
    end

    return data, byte_len
end

function decode_next(start_idx, bytes::Array{UInt8, 1})
    first_byte = bytes[start_idx]
    if first_byte == 0xf5
        return true, 1
    elseif first_byte == 0xf4
        return false, 1
    end 

    typ = first_byte & 0b1110_0000

    data, bytes_consumed =
        if typ == TYPE_0
            decode_unsigned(start_idx, bytes)
        elseif typ == TYPE_1
            data, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = -(Signed(data) + 1)
            data, bytes_consumed
        elseif typ == TYPE_4
            vec_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = Vector(vec_len)

            for i in 1:vec_len
                data[i], sub_bytes_consumed =
                    decode_next(bytes_consumed + 1, bytes)
                bytes_consumed += sub_bytes_consumed
            end

            data, bytes_consumed
        end

    return data, bytes_consumed
end

function decode(cbor_bytes::Array{UInt8, 1})
    data, _ = decode_next(1, cbor_bytes)
    return data
end

end
