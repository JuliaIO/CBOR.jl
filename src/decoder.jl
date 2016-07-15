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

function decode_unsigned(start_idx, unsigned_bytes::Array{UInt8, 1})
    addntl_info = unsigned_bytes[start_idx] & ADDNTL_INFO_MASK

    if addntl_info < SINGLE_BYTE_UINT_PLUS_ONE
        return addntl_info, sizeof(UInt8)
    end

    data, byte_len =
        if addntl_info == ADDNTL_INFO_UINT8
            zero(UInt8), sizeof(UInt8)
        elseif addntl_info == ADDNTL_INFO_UINT16
            zero(UInt16), sizeof(UInt16)
        elseif addntl_info == ADDNTL_INFO_UINT32
            zero(UInt32), sizeof(UInt32)
        elseif addntl_info == ADDNTL_INFO_UINT64
            zero(UInt64), sizeof(UInt64)
        end

    for i in 1:byte_len
        data <<= BITS_PER_BYTE
        data |= unsigned_bytes[start_idx + i]
    end

    return data, byte_len + 1
end

function decode_next(start_idx, bytes::Array{UInt8, 1})
    first_byte = bytes[start_idx]

    if first_byte == CBOR_TRUE_BYTE
        return true, 1
    elseif first_byte == CBOR_FALSE_BYTE
        return false, 1
    end

    typ = first_byte & TYPE_BITS_MASK

    data, bytes_consumed =
        if typ == TYPE_0
            decode_unsigned(start_idx, bytes)
        elseif typ == TYPE_1
            data, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = -(Signed(data) + 1)
            data, bytes_consumed
        elseif typ == TYPE_2
            byte_string_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            start_idx += bytes_consumed

            byte_string = bytes[start_idx:(start_idx + byte_string_len - 1)]
            bytes_consumed += byte_string_len

            byte_string, bytes_consumed
        elseif typ == TYPE_3
            string_bytes, bytes_consumed = decode_unsigned(start_idx, bytes)

            start_idx += bytes_consumed
            string =
                UTF8String(bytes[start_idx:(start_idx + string_bytes - 1)])
            bytes_consumed += string_bytes

            string, bytes_consumed
        elseif typ == TYPE_4
            vec_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = Vector(vec_len)

            for i in 1:vec_len
                data[i], sub_bytes_consumed =
                    decode_next(start_idx + bytes_consumed, bytes)
                bytes_consumed += sub_bytes_consumed
            end

            data, bytes_consumed
        elseif typ == TYPE_5
            map_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            map = Dict()

            for i in 1:map_len
                key, key_bytes =
                    decode_next(start_idx + bytes_consumed, bytes)
                bytes_consumed += key_bytes

                value, value_bytes =
                    decode_next(start_idx + bytes_consumed, bytes)
                bytes_consumed += value_bytes

                map[key] = value
            end

            map, bytes_consumed
        elseif typ == TYPE_6
            tag, bytes_consumed = decode_unsigned(start_idx, bytes)

            data =
                if tag == POS_BIG_INT_TAG || tag == NEG_BIG_INT_TAG
                    big_int_bytes, sub_bytes_consumed =
                        decode_next(start_idx + bytes_consumed, bytes)
                    bytes_consumed += sub_bytes_consumed

                    big_int = parse(BigInt, bytes2hex(big_int_bytes), HEX_BASE)
                    if tag == NEG_BIG_INT_TAG
                        big_int = -(big_int + 1)
                    end

                    big_int
                else
                    tagged_data, data_bytes =
                        decode_next(start_idx + bytes_consumed, bytes)
                    bytes_consumed += data_bytes

                    Pair(Tag(tag), tagged_data)
                end

            data, bytes_consumed
        elseif typ == TYPE_7
            addntl_info = bytes[start_idx] & ADDNTL_INFO_MASK

            float_byte_len =
                if addntl_info == ADDNTL_INFO_FLOAT64
                    SIZE_OF_FLOAT64
                elseif addntl_info == ADDNTL_INFO_FLOAT32
                    SIZE_OF_FLOAT32
                elseif addntl_info == ADDNTL_INFO_FLOAT16
                    error("Decoding of 16-bit float is not supported.")
                end

            hex2num(bytes2hex(
                bytes[(start_idx + 1):(start_idx + float_byte_len)]
            )), float_byte_len + 1
        end

    return data, bytes_consumed
end
