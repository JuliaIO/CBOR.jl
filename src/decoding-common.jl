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
    addntl_info = bytes[start_idx] & ADDNTL_INFO_MASK

    if addntl_info < SINGLE_BYTE_UINT_PLUS_ONE
        return addntl_info, sizeof(UInt8)
    elseif addntl_info == ADDNTL_INFO_UINT8
        data = zero(UInt8)
        byte_len = sizeof(UInt8)
    elseif addntl_info == ADDNTL_INFO_UINT16
        data = zero(UInt16)
        byte_len = sizeof(UInt16)
    elseif addntl_info == ADDNTL_INFO_UINT32
        data = zero(UInt32)
        byte_len = sizeof(UInt32)
    elseif addntl_info == ADDNTL_INFO_UINT64
        data = zero(UInt64)
        byte_len = sizeof(UInt64)
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
        data = byte_string
    elseif typ == TYPE_3
        buf = IOBuffer()
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            sub_utf8_string, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            write(buf, sub_utf8_string)
        end
        data = (VERSION < v"0.5.0") ? takebuf_string(buf) : String(take!(buf))
    elseif typ == TYPE_4
        vec = Vector()
        while bytes[start_idx + bytes_consumed] != BREAK_INDEF
            item, sub_bytes_consumed =
                decode_next(start_idx + bytes_consumed, bytes, with_iana)
            bytes_consumed += sub_bytes_consumed

            push!(vec, item)
        end
        data = vec
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
        data = dict
    end

    bytes_consumed += 1

    return data, bytes_consumed
end


@generated function type_from_dict(::Type{T}, dict) where T
    field_data = map(field-> :(convert(fieldtype(T, $(QuoteNode(field))), dict[$(string(field))])), fieldnames(T))
    Expr(:new, T, field_data...)
end

function decode_next(start_idx, bytes::Array{UInt8, 1}, with_iana::Bool)
    first_byte = bytes[start_idx]
    typ = first_byte & TYPE_BITS_MASK
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

            return Tag(tag, tagged_data)
        end

        if with_iana
            if tag == POS_BIG_INT_TAG || tag == NEG_BIG_INT_TAG
                big_int_bytes, sub_bytes_consumed =
                    decode_next(start_idx + bytes_consumed, bytes,
                                with_iana)
                bytes_consumed += sub_bytes_consumed

                big_int = parse(
                    BigInt, bytes2hex(big_int_bytes), base = HEX_BASE
                )
                if tag == NEG_BIG_INT_TAG
                    big_int = -(big_int + 1)
                end

                data = big_int
            elseif tag == 27 # Type Tag
                tagdata = retrieve_plain_pair()
                data = tagdata.data
                name, field_data_dict = data
                if startswith(name, "Julia/") # Julia Type
                    T = deserialize(IOBuffer(base64decode(name[7:end])))
                    data = type_from_dict(T, field_data_dict)
                else
                    data = tagdata # can't decode
                end
            else
                data = retrieve_plain_pair()
            end
        else
            data = retrieve_plain_pair()
        end

    elseif typ == TYPE_7
        addntl_info = first_byte & ADDNTL_INFO_MASK
        bytes_consumed = 1

        if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE + 1
            bytes_consumed += 1
            if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE
                simple_val = addntl_info
            else
                bytes_consumed += 1
                simple_val = bytes[start_idx + 1]
            end

            if simple_val == SIMPLE_FALSE
                data = false
            elseif simple_val == SIMPLE_TRUE
                data = true
            elseif simple_val == SIMPLE_NULL
                data = Null()
            elseif simple_val == SIMPLE_UNDEF
                data = Undefined()
            else
                data = Simple(simple_val)
            end
        else

            if addntl_info == ADDNTL_INFO_FLOAT64
                float_byte_len = SIZE_OF_FLOAT64
                FloatT = Float64; UintT = UInt64
            elseif addntl_info == ADDNTL_INFO_FLOAT32
                float_byte_len = SIZE_OF_FLOAT32
                FloatT = Float32; UintT = UInt32
            elseif addntl_info == ADDNTL_INFO_FLOAT16
                float_byte_len = SIZE_OF_FLOAT16
                FloatT = Float16; UintT = UInt16
            end

            bytes_consumed += float_byte_len
            hex = bytes2hex(
                bytes[(start_idx + 1):(start_idx + float_byte_len)]
            )
            data = reinterpret(FloatT, parse(UintT, hex, base = 16))
        end

    elseif first_byte & ADDNTL_INFO_MASK == ADDNTL_INFO_INDEF
        data, bytes_consumed =
            decode_next_indef(start_idx, bytes, typ, with_iana)

    elseif typ == TYPE_2
        byte_string_len, bytes_consumed =
            decode_unsigned(start_idx, bytes)
        start_idx += bytes_consumed

        data =
            bytes[start_idx:(start_idx + byte_string_len - 1)]
        bytes_consumed += byte_string_len

    elseif typ == TYPE_3
        string_bytes, bytes_consumed =
            decode_unsigned(start_idx, bytes)
        start_idx += bytes_consumed
        data = String(bytes[start_idx:(start_idx + string_bytes - 1)])

        bytes_consumed += string_bytes

    elseif typ == TYPE_4
        vec_len, bytes_consumed = decode_unsigned(start_idx, bytes)
        data = Vector(undef, vec_len)
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
