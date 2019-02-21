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

struct Tag{ID <: Union{Channel, Int}, T}
    id::ID
    data::T
end
Base.:(==)(a::Tag, b::Tag) = a.id == b.id && a.data == b.data
Tag(id::Integer, data) = Tag(Int(id), data)

include("constants.jl")
include("encoding-common.jl")
include("decoding-common.jl")

export encode
export decode, decode_with_iana
export Simple, Null, Undefined

function decode(cbor_bytes::Array{UInt8, 1})
    data, _ = decode_next(1, cbor_bytes, true)
    return data
end


function encode(data)
    bytes = UInt8[]
    encode(data, bytes)
    return bytes
end

end
