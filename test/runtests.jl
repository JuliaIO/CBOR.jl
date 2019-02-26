using Test
using CBOR
using DataStructures
import CBOR: Tag, decode, encode, SmallInteger
# Taken (and modified) from Appendix A of RFC 7049



two_way_test_vectors = [
    SmallInteger(0) => hex2bytes("00"),
    SmallInteger(1) => hex2bytes("01"),
    SmallInteger(10) => hex2bytes("0a"),
    SmallInteger(23) => hex2bytes("17"),
    SmallInteger(24) => hex2bytes("1818"),
    SmallInteger(25) => hex2bytes("1819"),

    UInt8(100) => hex2bytes("1864"),
    UInt16(1000) => hex2bytes("1903e8"),
    UInt32(1000000) => hex2bytes("1a000f4240"),
    UInt64(1000000000000) => hex2bytes("1b000000e8d4a51000"),
    # UInt128(18446744073709551615) => hex2bytes("1bffffffffffffffff"),
    # Int128(-18446744073709551616) => hex2bytes("3bffffffffffffffff"),
    SmallInteger(-1) => hex2bytes("20"),
    SmallInteger(-10) => hex2bytes("29"),
    Int8(-100) => hex2bytes("3863"),
    Int16(-1000) => hex2bytes("3903e7"),

    0.0f0 => hex2bytes("fa00000000"),
    -0.0f0 => hex2bytes("fa80000000"),
    1.0f0 => hex2bytes("fa3f800000"),
    1.1 => hex2bytes("fb3ff199999999999a"),
    1.5f0 => hex2bytes("fa3fc00000"),
    65504f0 => hex2bytes("fa477fe000"),
    100000f0 => hex2bytes("fa47c35000"),
    Float32(3.4028234663852886e+38) => hex2bytes("fa7f7fffff"),
    1.0e+300 => hex2bytes("fb7e37e43c8800759c"),
    Float32(5.960464477539063e-8) => hex2bytes("fa33800000"),
    Float32(0.00006103515625) => hex2bytes("fa38800000"),
    -4f0 => hex2bytes("fac0800000"),
    -4.1 => hex2bytes("fbc010666666666666"),

    false => hex2bytes("f4"),
    true => hex2bytes("f5"),
    nothing => hex2bytes("f6"),
    Undefined() => hex2bytes("f7"),

    Tag(0, "2013-03-21T20:04:00Z") =>
        hex2bytes("c074323031332d30332d32315432303a30343a30305a"),
    Tag(1, SmallInteger(1363896240)) => hex2bytes("c11a514b67b0"),
    Tag(1, 1363896240.5) => hex2bytes("c1fb41d452d9ec200000"),
    Tag(23, hex2bytes("01020304")) => hex2bytes("d74401020304"),
    Tag(24, hex2bytes("6449455446")) => hex2bytes("d818456449455446"),
    Tag(32, "http://www.example.com") =>
        hex2bytes("d82076687474703a2f2f7777772e6578616d706c652e636f6d"),

    UInt8[] => hex2bytes("40"),
    hex2bytes("01020304") => hex2bytes("4401020304"),

    "" => hex2bytes("60"),
    "a" => hex2bytes("6161"),
    "IETF" => hex2bytes("6449455446"),
    "\"\\" => hex2bytes("62225c"),
    "\u00fc" => hex2bytes("62c3bc"),
    "\u6c34" => hex2bytes("63e6b0b4"),

    [] => hex2bytes("80"),
    SmallInteger[1, 2, 3] => hex2bytes("83010203"),
    [SmallInteger(1), SmallInteger[2, 3], SmallInteger[4, 5]] => hex2bytes("8301820203820405"),
    SmallInteger[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25] =>
        hex2bytes("98190102030405060708090a0b0c0d0e0f101112131415161718181819"),

    Dict() => hex2bytes("a0"),
    OrderedDict(1=>2, 3=>4) => hex2bytes("a201020304"),
    OrderedDict("a"=>1, "b"=>[2, 3]) => hex2bytes("a26161016162820203"),
    OrderedDict("a"=>"A", "b"=>"B", "c"=>"C", "d"=>"D", "e"=>"E") =>
        hex2bytes("a56161614161626142616361436164614461656145"),

    ["a", Dict("b"=>"c")] => hex2bytes("826161a161626163")
]

@testset "two way" begin
    for (data, bytes) in two_way_test_vectors
        @test data == decode(encode(data))
        # TODO, Julia's base dict are not ordered, so we can't exactly match
        # the bytes right now...
        # OrderedDict's are not in base, so should be serialized as an arbitrary
        # Julia struct!
        if !(data isa OrderedDict)
            @test isequal(bytes, encode(data))
            @test isequal(data, decode(bytes))
        end
    end
end


bytes_to_data_test_vectors = [
    hex2bytes("fa7fc00000") => NaN32,
    hex2bytes("fa7f800000") => Inf32,
    hex2bytes("faff800000") => -Inf32,
    hex2bytes("fb7ff8000000000000") => NaN,
    hex2bytes("fb7ff0000000000000") => Inf,
    hex2bytes("fbfff0000000000000") => -Inf
]

@testset "bytes to data" begin
    for (bytes, data) in bytes_to_data_test_vectors
        @test isequal(data, decode(bytes))
    end
end

iana_test_vector = [
    BigInt(18446744073709551616) => hex2bytes("c249010000000000000000"),
    BigInt(-18446744073709551617) => hex2bytes("c349010000000000000000")
]

@testset "BigInt iana" begin
    for (data, bytes) in iana_test_vector
        @test isequal(bytes, encode(data))
        @test isequal(data, decode(bytes))
    end
end

indef_length_coll_test_vectors = [
    Any[["Hello", " ", "world"], "Hello world", String] =>
        hex2bytes("7f6548656c6c6f612065776f726c64ff"),
    Any[b"Hello world", b"Hello world", Array{UInt8, 1}] =>
        hex2bytes("5f18481865186c186c186f18201877186f1872186c1864ff"),
    Any[[1, 2.3, "Twiddle"], [1, 2.3, "Twiddle"], AbstractVector] =>
        hex2bytes("9f01fb40026666666666666754776964646c65ff"),
    Any[OrderedDict(1=>2, 3.2=>"3.2"), OrderedDict(1=>2, 3.2=>"3.2"),
        AbstractDict] => hex2bytes("bf0102fb400999999999999a63332e32ff")
]

coll = []

function list_producer(c::Channel)
    for e in coll
        put!(c::Channel,e)
    end
end
function map_producer(c::Channel)
    for (k, v) in coll
        put!(c::Channel,k)
        put!(c::Channel,v)
    end
end
@testset "ifndef length collections" begin
    for (data, bytes) in indef_length_coll_test_vectors
        global coll
        coll = data[1]
        task = if data[3] <: AbstractDict
            Channel(map_producer)
        else
            Channel(list_producer)
        end
        @test isequal(bytes, encode(Tag(task, data[3])))
        @test isequal(data[2], decode(bytes))
    end
end


using Serialization
@which deserialize(IOBuffer())
