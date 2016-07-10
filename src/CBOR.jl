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

function encode_unsigned_with_type(typ_bits::UInt8, num::Unsigned)

    if num < 0x18 # 0 to 23
        return UInt8[typ_bits | num]
    elseif num < 0x100 # 8 bit unsigned integer
        return UInt8[typ_bits | 0x18, num]
    end

    hex_str = hex(num)
    if isodd(length(hex_str))
        hex_str = "0" * hex_str # hex2bytes() doesn't accept odd length strings
    end
    bytes_array = hex2bytes(hex_str)

    uint_byte_len = 0

    if num < 0x10000 # 16 bit unsigned integer
        unshift!(bytes_array, typ_bits | 0x19)
        uint_byte_len = 2
    elseif num < 0x100000000 # 32 bit unsigned integer
        unshift!(bytes_array, typ_bits | 0x1a)
        uint_byte_len = 4
    else # 64 bit unsigned integer
        unshift!(bytes_array, typ_bits | 0x1b)
        uint_byte_len = 8
    end

    # pad out some zeros in the byte array if needed
    for _ in 1:(uint_byte_len - length(bytes_array) + 1)
        insert!(bytes_array, 2, zero(UInt8))
    end

    return bytes_array
end

function encode(num::Unsigned)
    encode_unsigned_with_type(TYPE_0, num)
end

function encode(num::Signed)
    if num < 0
        return encode_unsigned_with_type(TYPE_1, Unsigned(-num - 1))
    else
        return encode_unsigned_with_type(TYPE_0, Unsigned(num))
    end
end

function encode(byte_str::ASCIIString)
    bytes_array = encode_unsigned_with_type(
        TYPE_2, Unsigned(length(byte_str))
    )

    for c in byte_str
        push!(bytes_array, UInt8(c))
    end

    return bytes_array
end

function encode(utf8_str::UTF8String)
    bytes_array = encode_unsigned_with_type(
        TYPE_3, Unsigned(sizeof(utf8_str))
    )

    for c in utf8_str.data
        push!(bytes_array, UInt8(c))
    end

    return bytes_array
end

function encode(list::Union{AbstractVector,Tuple})
    bytes_array = encode_unsigned_with_type(
        TYPE_4, Unsigned(length(list))
    )

    for e in list
        append!(bytes_array, encode(e))
    end

    return bytes_array
end

function encode(map::Associative)
    bytes_array = encode_unsigned_with_type(
        TYPE_5, Unsigned(length(map))
    )

    for (key, value) in map
        append!(bytes_array, encode(key))
        append!(bytes_array, encode(value))
    end

    return bytes_array
end

function encode(data)
    cbor_bytes = UInt8[]
    return cbor_bytes
end

function decode(code)

end

end
