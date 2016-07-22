include("../src/CBOR.jl")

using Base.Test
using CBOR
using DataStructures

# Taken (and modified) from Appendix A of RFC 7049

two_way_test_vectors = Dict(
    0 => hex2bytes("00"),
    1 => hex2bytes("01"),
    10 => hex2bytes("0a"),
    23 => hex2bytes("17"),
    24 => hex2bytes("1818"),
    25 => hex2bytes("1819"),
    100 => hex2bytes("1864"),
    1000 => hex2bytes("1903e8"),
    1000000 => hex2bytes("1a000f4240"),
    1000000000000 => hex2bytes("1b000000e8d4a51000"),
    18446744073709551615 => hex2bytes("1bffffffffffffffff"),
    -18446744073709551616 => hex2bytes("3bffffffffffffffff"),
    -1 => hex2bytes("20"),
    -10 => hex2bytes("29"),
    -100 => hex2bytes("3863"),
    -1000 => hex2bytes("3903e7"),

    0.0 => hex2bytes("fa00000000"),
    -0.0 => hex2bytes("fa80000000"),
    1.0 => hex2bytes("fa3f800000"),
    1.1 => hex2bytes("fb3ff199999999999a"),
    1.5 => hex2bytes("fa3fc00000"),
    65504.0 => hex2bytes("fa477fe000"),
    100000.0 => hex2bytes("fa47c35000"),
    3.4028234663852886e+38 => hex2bytes("fa7f7fffff"),
    1.0e+300 => hex2bytes("fb7e37e43c8800759c"),
    5.960464477539063e-8 => hex2bytes("fa33800000"),
    0.00006103515625 => hex2bytes("fa38800000"),
    -4.0 => hex2bytes("fac0800000"),
    -4.1 => hex2bytes("fbc010666666666666"),

    false => hex2bytes("f4"),
    true => hex2bytes("f5"),
    Null() => hex2bytes("f6"),
    Undefined() => hex2bytes("f7"),
    Simple(16) => hex2bytes("f0"),
    Simple(24) => hex2bytes("f818"),
    Simple(255) => hex2bytes("f8ff"),

    Pair(0, "2013-03-21T20:04:00Z") => hex2bytes("c074323031332d30332d32315432303a30343a30305a"),
    Pair(1, 1363896240) => hex2bytes("c11a514b67b0"),
    Pair(1, 1363896240.5) => hex2bytes("c1fb41d452d9ec200000"),
    Pair(23, hex2bytes("01020304")) => hex2bytes("d74401020304"),
    Pair(24, hex2bytes("6449455446")) => hex2bytes("d818456449455446"),
    Pair(32, "http://www.example.com") => hex2bytes("d82076687474703a2f2f7777772e6578616d706c652e636f6d"),

    UInt8[] => hex2bytes("40"),
    hex2bytes("01020304") => hex2bytes("4401020304"),

    "" => hex2bytes("60"),
    "a" => hex2bytes("6161"),
    "IETF" => hex2bytes("6449455446"),
    "\"\\" => hex2bytes("62225c"),
    "\u00fc" => hex2bytes("62c3bc"),
    "\u6c34" => hex2bytes("63e6b0b4"),

    [] => hex2bytes("80"),
    [1, 2, 3] => hex2bytes("83010203"),
    Any[1, [2, 3], [4, 5]] => hex2bytes("8301820203820405"),
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25] => hex2bytes("98190102030405060708090a0b0c0d0e0f101112131415161718181819"),

    Dict() => hex2bytes("a0"),
    OrderedDict(1=>2, 3=>4) => hex2bytes("a201020304"),
    OrderedDict("a"=>1, "b"=>[2, 3]) => hex2bytes("a26161016162820203"),
    OrderedDict("a"=>"A", "b"=>"B", "c"=>"C", "d"=>"D", "e"=>"E") => hex2bytes("a56161614161626142616361436164614461656145"),

    ["a", Dict("b"=>"c")] => hex2bytes("826161a161626163")
)

for (data, bytes) in two_way_test_vectors
    @test isequal(bytes, encode(data))
    @test isequal(data, decode(bytes))
end

bytes_to_data_test_vectors = Dict(
    hex2bytes("fa7fc00000") => NaN32,
    hex2bytes("fa7f800000") => Inf32,
    hex2bytes("faff800000") => -Inf32,
    hex2bytes("fb7ff8000000000000") => NaN,
    hex2bytes("fb7ff0000000000000") => Inf,
    hex2bytes("fbfff0000000000000") => -Inf
)

for (bytes, data) in bytes_to_data_test_vectors
    @test isequal(data, decode(bytes))
end

iana_test_vector = Dict(
    BigInt(18446744073709551616) => hex2bytes("c249010000000000000000"),
    BigInt(-18446744073709551617) => hex2bytes("c349010000000000000000")
)

for (data, bytes) in iana_test_vector
    @test isequal(bytes, encode(data))
    @test isequal(data, decode_with_iana(bytes))
end
