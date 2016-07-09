module CBOR

function encode(bool::Bool)
    if bool
        return UInt8[0xf5,]
    end
    return UInt8[0xf4,]
end

function encode(data)
    cbor_bytes = UInt8[]
    return cbor_bytes
end

function decode(code)

end

end
