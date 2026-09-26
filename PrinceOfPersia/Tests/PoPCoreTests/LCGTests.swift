import Testing
@testable import PoPCore

// M3: the MSVC rand() LCG.
//
// Expected values computed by running the reference formula directly:
//   s = (s * 214013 + 2531011) & 0xffffffff;  result = (s >>> 16) % (max + 1)

@Test func seedOneMatchesTheReferenceSequence() {
    var rng = LCG(seed: 1)
    let values = (0..<6).map { _ in rng.next(upperBound: 255) }
    #expect(values == [41, 35, 190, 132, 225, 108])
}

@Test(arguments: [(1, [41, 35, 190, 132, 225, 108]),
                   (7, [61, 14, 111, 128, 161, 116]),
                   (22, [110, 216, 42, 118, 255, 137])])
func seedsMatchTheReference(seed: Int, expected: [Int]) {
    var rng = LCG(seed: seed)
    #expect((0..<expected.count).map { _ in rng.next(upperBound: 255) } == expected)
}

@Test func rawStateMatchesTheReference() {
    // The three internal states after seeding with 1. Verifying the state itself, not
    // just the derived output, pins the multiplier and increment exactly.
    var rng = LCG(seed: 1)
    _ = rng.next(upperBound: 255)
    #expect(rng.state == 2_745_024)
    _ = rng.next(upperBound: 255)
    #expect(rng.state == 3_357_800_067)
    _ = rng.next(upperBound: 255)
    #expect(rng.state == 415_139_642)
}

@Test func wrappingIsModularNotTrapping() {
    // Swift traps on overflowing Int arithmetic. The reference's & 0xffffffff is a
    // modular wrap, so the operators must be &* and &+.
    var rng = LCG(state: .max)
    _ = rng.next(upperBound: 255)
    #expect(rng.state == UInt32.max &* 214_013 &+ 2_531_011)
}

@Test func theGeneratorIsReproducible() {
    var a = LCG(seed: 22)
    var b = LCG(seed: 22)
    for _ in 0..<50 {
        #expect(a.next(upperBound: 1000) == b.next(upperBound: 1000))
    }
    #expect(a == b)
}

@Test func resultsStayInsideTheRequestedBound() {
    var rng = LCG(seed: 3)
    for bound in [0, 1, 7, 255, 1000] {
        for _ in 0..<200 {
            let value = rng.next(upperBound: bound)
            #expect(value >= 0)
            #expect(value <= bound)
        }
    }
}
