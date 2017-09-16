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

function decode_unsigned(start_idx, bytes::Array{UInt8, 1})
    const addntl_info = bytes[start_idx] & ADDNTL_INFO_MASK

    if addntl_info < SINGLE_BYTE_UINT_PLUS_ONE
        return addntl_info, sizeof(UInt8)
    elseif addntl_info == ADDNTL_INFO_UINT8
        const data = zero(UInt8)
        const byte_len = sizeof(UInt8)
    elseif addntl_info == ADDNTL_INFO_UINT16
        const data = zero(UInt16)
        const byte_len = sizeof(UInt16)
    elseif addntl_info == ADDNTL_INFO_UINT32
        const data = zero(UInt32)
        const byte_len = sizeof(UInt32)
    elseif addntl_info == ADDNTL_INFO_UINT64
        const data = zero(UInt64)
        const byte_len = sizeof(UInt64)
    end

    for i in 1:byte_len
        data <<= BITS_PER_BYTE
        data |= bytes[start_idx + i]
    end

    return data, byte_len + 1
end

function decode_next_indef(start_idx, bytes::Array{UInt8, 1}, typ::UInt8,
                           with_iana::Bool)
    bytes_consumed = 1

    if typ == TYPE_2
        byte_string = UInt8[]
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            sub_byte_string, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            push!(byte_string, sub_byte_string)
        end
        const data = byte_string
    elseif typ == TYPE_3
        buf = IOBuffer()
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            sub_utf8_string, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            write(buf, sub_utf8_string)
        end
        const data = String(take!(buf))
    elseif typ == TYPE_4
        vec = Vector()
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            item, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            push!(vec, item)
        end
        const data = vec
    elseif typ == TYPE_5
        dict = Dict()
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            key, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            value, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            dict[key] = value
        end
        const data = dict
    end

    bytes_consumed += 1

    return data, bytes_consumed
end

function decode_next(start_idx, bytes::Array{UInt8, 1}, with_iana::Bool)
    const first_byte = bytes[start_idx]
    const typ = first_byte & TYPE_BITS_MASK

        if typ == TYPE_0
            data, bytes_consumed = decode_unsigned(start_idx, bytes)

        elseif typ == TYPE_1
            data, bytes_consumed = decode_unsigned(start_idx, bytes)
            if (i = Int128(data) + 1) > typemax(Int64)
                data = -i
            else
                data = -(Signed(data) + 1)
            end

        elseif typ == TYPE_6
            tag, bytes_consumed = decode_unsigned(start_idx, bytes)

            function retrieve_plain_pair()
                tagged_data, data_bytes =
                    decode_next(start_idx + bytes_consumed, bytes,
                                with_iana)
                bytes_consumed += data_bytes

                return Pair(tag, tagged_data)
            end

            if with_iana
                if tag == POS_BIG_INT_TAG || tag == NEG_BIG_INT_TAG
                    big_int_bytes, sub_bytes_consumed =
                        decode_next(start_idx + bytes_consumed, bytes,
                                    with_iana)
                    bytes_consumed += sub_bytes_consumed

                    big_int = parse(BigInt, bytes2hex(big_int_bytes),
                                    HEX_BASE)
                    if tag == NEG_BIG_INT_TAG
                        big_int = -(big_int + 1)
                    end

                    const data = big_int
                else
                    const data = retrieve_plain_pair()
                end
            else
                const data = retrieve_plain_pair()
            end

        elseif typ == TYPE_7
            const addntl_info = first_byte & ADDNTL_INFO_MASK
            bytes_consumed = 1

            if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE + 1
                bytes_consumed += 1
                if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE
                    const simple_val = addntl_info
                else
                    bytes_consumed += 1
                    const simple_val = bytes[start_idx + 1]
                end

                if simple_val == SIMPLE_FALSE
                    const data = false
                elseif simple_val == SIMPLE_TRUE
                    const data = true
                elseif simple_val == SIMPLE_NULL
                    const data = Null()
                elseif simple_val == SIMPLE_UNDEF
                    const data = Undefined()
                else
                    const data = Simple(simple_val)
                end
            else
                if addntl_info == ADDNTL_INFO_FLOAT64
                    const float_byte_len = SIZE_OF_FLOAT64
                elseif addntl_info == ADDNTL_INFO_FLOAT32
                    const float_byte_len = SIZE_OF_FLOAT32
                elseif addntl_info == ADDNTL_INFO_FLOAT16
                    error("Decoding 16-bit floats isn't supported.")
                end

                bytes_consumed += float_byte_len
                const data = hex2num(bytes2hex(
                    bytes[(start_idx + 1):(start_idx + float_byte_len)]
                ))
            end

        elseif first_byte & ADDNTL_INFO_MASK == ADDNTL_INFO_INDEF
            data, bytes_consumed =
                decode_next_indef(start_idx, bytes, typ, with_iana)

        elseif typ == TYPE_2
            byte_string_len, bytes_consumed =
                decode_unsigned(start_idx, bytes)
            start_idx += bytes_consumed

            const data =
                bytes[start_idx:(start_idx + byte_string_len - 1)]
            bytes_consumed += byte_string_len

        elseif typ == TYPE_3
            string_bytes, bytes_consumed =
                decode_unsigned(start_idx, bytes)
            start_idx += bytes_consumed
            const data =
                String(bytes[start_idx:(start_idx + string_bytes - 1)])
            bytes_consumed += string_bytes

        elseif typ == TYPE_4
            vec_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = Vector(vec_len)
            for i in 1:vec_len
                data[i], sub_bytes_consumed =
                    decode_next(start_idx + bytes_consumed, bytes, with_iana)
                bytes_consumed += sub_bytes_consumed
            end

        elseif typ == TYPE_5
            map_len, bytes_consumed = decode_unsigned(start_idx, bytes)
            data = Dict()
            for i in 1:map_len
                key, key_bytes =
                    decode_next(start_idx + bytes_consumed, bytes, with_iana)
                bytes_consumed += key_bytes

                value, value_bytes =
                    decode_next(start_idx + bytes_consumed, bytes, with_iana)
                bytes_consumed += value_bytes

                data[key] = value
            end
        end

    return data, bytes_consumed
end
