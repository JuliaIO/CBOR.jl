module CBOR

function encode(bool::Bool)
    return UInt8[0xf4 + bool,]
end

function encode_unsigned_with_type(typ::UInt8, num::Unsigned)
    three_type_bits = typ << 5

    if num < 0x18 # 0 to 23
        return UInt8[three_type_bits | num,]
    elseif num < 0x100 # 8 bit unsigned integer
        return UInt8[num, three_type_bits | 0x18]
    end

    hex_str = hex(num)
    if isodd(length(hex_str))
        hex_str = "0" * hex_str # hex2bytes() doesn't accept odd length strings
    end
    bytes_array = hex2bytes(hex_str)

    uint_byte_len = 0

    if num < 0x10000 # 16 bit unsigned integer
        unshift!(bytes_array, three_type_bits | 0x19)
        uint_byte_len = 2
    elseif num < 0x100000000 # 32 bit unsigned integer
        unshift!(bytes_array, three_type_bits | 0x1a)
        uint_byte_len = 4
    else # 64 bit unsigned integer
        unshift!(bytes_array, three_type_bits | 0x1b)
        uint_byte_len = 8
    end

    # pad out some zeros in the byte array if needed
    for _ in 1:(uint_byte_len - length(bytes_array) + 1)
        insert!(bytes_array, 2, zero(UInt8))
    end

    return bytes_array
end

function encode(num::Unsigned)
    encode_unsigned_with_type(zero(UInt8), num)
end

function encode(num::Signed)
    if num < 0
        return encode_unsigned_with_type(one(UInt8), Unsigned(-num - 1))
    else
        return encode_unsigned_with_type(zero(UInt8), Unsigned(num))
    end
end

function encode(data)
    cbor_bytes = UInt8[]
    return cbor_bytes
end

function decode(code)

end

end
