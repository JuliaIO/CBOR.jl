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

using Printf, Serialization, Base64

num2hex(n) = string(n, base = 16, pad = sizeof(n) * 2)
num2hex(n::AbstractFloat) = num2hex(reinterpret(Unsigned, n))
hex2num(s) = reinterpret(Float64, parse(UInt64, s, base = 16))
hex(n) = string(n, base = 16)

struct Tag{T}
    id::Int
    data::T
end
Base.:(==)(a::Tag, b::Tag) = a.id == b.id && a.data == b.data
Tag(id::Integer, data) = Tag(Int(id), data)

struct Decoder{IOType}
    io::IOType
    reference_cache::Vector{Any}
end
Decoder(io::IOType) where IOType <: IO = Decoder{IOType}(io, [])

Base.read(io::Decoder, T::Type) = read(io.io, T)
Base.read(io::Decoder, n::Integer) = read(io.io, n)
Base.skip(io::Decoder, amount) = read(io.io, amount)

struct Encoder{IOType}
    io::IOType
    encode_references::Bool
    references::IdDict{Any, Int}
end
Base.write(io::Encoder, data) = write(io.io, data)

function Encoder(io::IOType, encode_references = false) where IOType <: IO
    Encoder{IOType}(io, encode_references, IdDict{Any, Int}())
end

"""
A CBOR reference for CBOR Reference types (Tag 28/29)
"""
struct Reference
    index::Int
end

include("constants.jl")
include("encode.jl")
include("decode.jl")

export encode
export decode, decode_with_iana
export Simple, Null, Undefined

replace_references!(refs, x) = x
replace_references!(refs, x::Reference) = refs[x.index]
replace_references!(refs, x::Vector) = map!(x-> replace_references!(refs, x), x, x)

function replace_references!(refs, dict::Dict)
    for (k, v) in dict
        if k isa Reference
            delete!(dict, k)
            k = replace_references!(refs, k)
        end
        dict[k] = replace_references!(refs, v)
    end
    dict
end


function decode(data::Vector{UInt8})
    return decode(IOBuffer(data))
end

function decode(io::IO)
    dio = Decoder(io)
    data = decode(dio)
    return replace_references!(dio.reference_cache, data)
end


function encode(data; with_references = false)
    io = IOBuffer()
    encode(io, data; with_references = with_references)
    return take!(io)
end

function encode(io::IO, data; with_references = false)
    encode(Encoder(io, with_references), data)
end

end
