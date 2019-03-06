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

function type_from_fields(::Type{T}, fields) where T
    ccall(:jl_new_structv, Any, (Any, Ptr{Cvoid}, UInt32), T, fields, length(fields))
end

function peekbyte(io::Decoder)
    mark(io.io)
    byte = read(io, UInt8)
    reset(io.io)
    return byte
end

struct UndefIter{Decoder, F}
    f::F
    io::Decoder
end
Base.IteratorSize(::Type{<: UndefIter}) = Base.SizeUnknown()

function Base.iterate(x::UndefIter, state = nothing)
    peekbyte(x.io) == BREAK_INDEF && return nothing
    return x.f(x.io), nothing
end

function decode_ntimes(f, io::Decoder)
    first_byte = peekbyte(io)
    if (first_byte & ADDNTL_INFO_MASK) == ADDNTL_INFO_INDEF
        skip(io, 1) # skip first byte
        return UndefIter(f, io)
    else
        return (f(io) for i in 1:decode_unsigned(io))
    end
end

function decode_unsigned(io::Decoder)
    addntl_info = read(io, UInt8) & ADDNTL_INFO_MASK
    if addntl_info < SINGLE_BYTE_UINT_PLUS_ONE
        return addntl_info
    elseif addntl_info == ADDNTL_INFO_UINT8
        return bswap(read(io, UInt8))
    elseif addntl_info == ADDNTL_INFO_UINT16
        return bswap(read(io, UInt16))
    elseif addntl_info == ADDNTL_INFO_UINT32
        return bswap(read(io, UInt32))
    elseif addntl_info == ADDNTL_INFO_UINT64
        return bswap(read(io, UInt64))
    else
        error("Unknown Int type")
    end
end



decode(io::Decoder, ::Val{TYPE_0}) = decode_unsigned(io)

function decode(io::Decoder, ::Val{TYPE_1})
    data = signed(decode_unsigned(io))
    if (i = Int128(data) + one(data)) > typemax(Int64)
        return -i
    else
        return -(data + one(data))
    end
end

"""
Decode Byte Array
"""
function decode(io::Decoder, ::Val{TYPE_2})
    if (peekbyte(io) & ADDNTL_INFO_MASK) == ADDNTL_INFO_INDEF
        skip(io, 1)
        result = IOBuffer()
        while peekbyte(io) !== BREAK_INDEF
            write(result, decode(io))
        end
        return take!(result)
    else
        return read(io, decode_unsigned(io))
    end
end

"""
Decode String
"""
function decode(io::Decoder, ::Val{TYPE_3})
    if (peekbyte(io) & ADDNTL_INFO_MASK) == ADDNTL_INFO_INDEF
        skip(io, 1)
        result = IOBuffer()
        while peekbyte(io) !== BREAK_INDEF
            write(result, decode(io))
        end
        return String(take!(result))
    else
        return String(read(io, decode_unsigned(io)))
    end
end

"""
Decode Vector of arbitrary elements
"""
function decode(io::Decoder, ::Val{TYPE_4})
    return map(identity, decode_ntimes(decode, io))
end

"""
Decode Dict
"""
function decode(io::Decoder, ::Val{TYPE_5})
    return Dict(decode_ntimes(io) do io
        decode(io) => decode(io)
    end)
end


"""
Decode Tagged type
"""
function decode(io::Decoder, ::Val{TYPE_6})
    tag = decode_unsigned(io)
    data = decode(io)
    if tag in (POS_BIG_INT_TAG, NEG_BIG_INT_TAG)
        big_int = parse(
            BigInt, bytes2hex(data), base = HEX_BASE
        )
        if tag == NEG_BIG_INT_TAG
            big_int = -(big_int + 1)
        end
        return big_int
    end
    if tag == MARK_SHARED_VALUE
        push!(io.reference_cache, data)
        return data
    end
    if tag == REFERENCE_SHARED_VALUE
        if checkbounds(Bool, io.reference_cache, data + 1)
            # if the index is in bounds, we already know the referenced object
            # and can immediately return it
            return io.reference_cache[data + 1]
        else
            # The reference points to an object that isn't constructed yet
            return Reference(data + 1)
        end
    end
    if tag == CUSTOM_LANGUAGE_TYPE # Type Tag
        name = data[1]
        object_serialized = data[2]
        if startswith(name, "Julia/") # Julia Type
            return deserialize(IOBuffer(object_serialized))
        end
    end
    # TODO implement other common tags!
    return Tag(tag, data)
end

function decode(io::Decoder, ::Val{TYPE_7})
    first_byte = read(io, UInt8)
    addntl_info = first_byte & ADDNTL_INFO_MASK
    if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE + 1
        simple_val = if addntl_info < SINGLE_BYTE_SIMPLE_PLUS_ONE
            addntl_info
        else
            read(io, UInt8)
        end
        if simple_val == SIMPLE_FALSE
            return false
        elseif simple_val == SIMPLE_TRUE
            return true
        elseif simple_val == SIMPLE_NULL
            return nothing
        elseif simple_val == SIMPLE_UNDEF
            return Undefined()
        else
            return Simple(simple_val)
        end
    else
        if addntl_info == ADDNTL_INFO_FLOAT64
            return reinterpret(Float64, ntoh(read(io, UInt64)))
        elseif addntl_info == ADDNTL_INFO_FLOAT32
            return reinterpret(Float32, ntoh(read(io, UInt32)))
        elseif addntl_info == ADDNTL_INFO_FLOAT16
            return reinterpret(Float16, ntoh(read(io, UInt16)))
        else
            error("Unsupported Float Type!")
        end
    end
end

function decode(io::Decoder)
    # leave startbyte in io
    first_byte = peekbyte(io)
    typ = first_byte & TYPE_BITS_MASK
    typ == TYPE_0 && return decode(io, Val(TYPE_0))
    typ == TYPE_1 && return decode(io, Val(TYPE_1))
    typ == TYPE_2 && return decode(io, Val(TYPE_2))
    typ == TYPE_3 && return decode(io, Val(TYPE_3))
    typ == TYPE_4 && return decode(io, Val(TYPE_4))
    typ == TYPE_5 && return decode(io, Val(TYPE_5))
    typ == TYPE_6 && return decode(io, Val(TYPE_6))
    typ == TYPE_7 && return decode(io, Val(TYPE_7))
end
