import XCTest

/// The Kokoro text rules against the reference, scripts/voices/norm.py,
/// with its ordinal and letter-number rules: 3rd "third", G5 "G five",
/// 5A "five A". The port must say exactly what the reference says.
final class KokoroTextTests: XCTestCase {
    private let reference: [(String, String)] = [
        ("Take US 101 North", "Take U S one oh one North"),
        ("Merge onto I-80 East", "Merge onto I eighty East"),
        ("Continue on CA 17 South", "Continue on C A seventeen South"),
        ("Turn left onto Hwy 9", "Turn left onto Highway nine"),
        ("Take Route 66", "Take Route sixty six"),
        ("Keep right onto SR 85", "Keep right onto State Route eighty five"),
        ("Take Interstate 5", "Take Interstate five"),
        ("Take I-405 S toward Long Beach", "Take I four oh five South toward Long Beach"),
        ("Take I-280 N", "Take I two eighty North"),
        ("Merge onto US-50", "Merge onto U S fifty"),
        ("Turn right onto Main St", "Turn right onto Main Street"),
        ("Turn left onto El Camino Real", "Turn left onto El Camino Real"),
        ("Continue onto Stevens Creek Blvd", "Continue onto Stevens Creek Boulevard"),
        ("Turn right onto Foothill Expy", "Turn right onto Foothill Expy"),
        ("Turn left onto Oak Ave", "Turn left onto Oak Avenue"),
        ("Turn right onto Mill Rd", "Turn right onto Mill Road"),
        ("Turn left onto Ocean Dr", "Turn left onto Ocean Drive"),
        ("Turn right onto W 3rd St", "Turn right onto West third Street"),
        ("Turn left onto N 1st St", "Turn left onto North first Street"),
        ("Turn right onto E Santa Clara St", "Turn right onto East Santa Clara Street"),
        ("In 2.5 mi, take exit 42", "In two point five miles, take exit forty two"),
        ("Speed limit 65 mph", "Speed limit sixty five miles per hour"),
        ("Fog ahead, visibility 500 ft", "Fog ahead, visibility five hundred feet"),
        ("In 1.2 km, turn left", "In one point two kilometers, turn left"),
        ("CHP reports a crash ahead", "C H P reports a crash ahead"),
        ("Chain controls on I-80 at Kingvale", "Chain controls on I eighty at Kingvale"),
        ("Closure on Hwy 1 from 7 PM to 5 AM", "Closure on Highway one from seven PM to five AM"),
        ("Exit 398B", "Exit three hundred ninety eight B"),
        ("Road closed for 1234 feet", "Road closed for one thousand two hundred thirty four feet"),
        ("A crash 0.3 miles ahead", "A crash zero point three miles ahead"),
        ("Turn left in 15 meters", "Turn left in fifteen meters"),
        ("In 300 meters, turn right onto 24th Avenue", "In three hundred meters, turn right onto twenty fourth Avenue"),
        ("Take exit 1000000 toward 2000001", "Take exit one zero zero zero zero zero zero toward two zero zero zero zero zero one"),
        ("Route 100 and Route 105", "Route one oh zero and Route one oh five"),
        ("Take I 5 north", "Take I five north"),
        ("Destination is 12 miles ahead", "Destination is twelve miles ahead"),
        ("Police reported ahead, in half a mile", "Police reported ahead, in half a mile"),
        ("Weather station: 21 degrees", "Weather station: twenty one degrees"),
        ("Exit 12 toward CA-1 S", "Exit twelve toward C A one South"),
        ("Highway 101 at 9th St", "Highway one oh one at ninth Street"),
        ("Turn right onto 3rd St", "Turn right onto third Street"),
        ("21st Ave", "twenty first Avenue"),
        ("Take exit 5A", "Take exit five A"),
        ("G5 Rd", "G five Road"),
        ("112th St", "one hundred twelfth Street"),
        ("I-405 N", "I four oh five North"),
        ("101st Street", "one hundred first Street"),
        ("Take the 2nd exit", "Take the second exit"),
        ("Exit 80th Ave", "Exit eightieth Avenue"),
        ("Turn onto Ab12 Ln", "Turn onto Ab twelve Ln"),
        ("AB12 is closed", "A B twelve is closed"),
        ("Exit 12th St and 5B", "Exit twelfth Street and five B"),
    ]

    func testMatchesTheReferenceNormalizer() {
        for (input, expected) in reference {
            XCTAssertEqual(KokoroText.normalize(input), expected, "for \(input)")
        }
    }

    func testNumberWords() {
        let cases: [(Int, String)] = [
            (0, "zero"), (7, "seven"), (19, "nineteen"), (20, "twenty"), (21, "twenty one"), (99, "ninety nine"),
            (100, "one hundred"), (101, "one hundred one"), (110, "one hundred ten"), (999, "nine hundred ninety nine"),
            (1000, "one thousand"), (1001, "one thousand one"), (12345, "twelve thousand three hundred forty five"),
            (999_999, "nine hundred ninety nine thousand nine hundred ninety nine"),
            (1_000_000, "one zero zero zero zero zero zero"),
        ]
        for (n, expected) in cases { XCTAssertEqual(KokoroText.words(n), expected, "for \(n)") }
    }

    func testOrdinals() {
        let cases: [(Int, String)] = [
            (1, "first"), (2, "second"), (3, "third"), (4, "fourth"), (5, "fifth"), (8, "eighth"), (9, "ninth"),
            (11, "eleventh"), (12, "twelfth"), (20, "twentieth"), (21, "twenty first"), (40, "fortieth"),
            (100, "one hundredth"), (101, "one hundred first"), (112, "one hundred twelfth"),
        ]
        for (n, expected) in cases { XCTAssertEqual(KokoroText.ordinal(n), expected, "for \(n)") }
    }

    func testRouteNumbersAreSaidTheWayDriversSayThem() {
        let cases: [(String, String)] = [
            ("5", "five"), ("80", "eighty"), ("101", "one oh one"), ("405", "four oh five"), ("280", "two eighty"),
            ("110", "one ten"), ("001", "one"), ("1234", "one thousand two hundred thirty four"),
        ]
        for (n, expected) in cases { XCTAssertEqual(KokoroText.routeNumber(n), expected, "for \(n)") }
    }

    func testUnknownWordsAreFoundSoTheSystemVoiceCanSayTheSentence() {
        let lexicon: Set<String> = ["turn", "right", "onto", "west", "street", "main", "don't"]
        XCTAssertEqual(KokoroText.unknownWords("Turn right onto Main Street.", known: lexicon.contains), [])
        let normalized = KokoroText.normalize("Turn right onto W 3rd St")
        XCTAssertEqual(KokoroText.unknownWords(normalized, known: lexicon.contains), ["third"])
        XCTAssertEqual(KokoroText.unknownWords("Don\u{2019}t turn onto Zzyzx Zzyzx", known: lexicon.contains), ["zzyzx"])
    }

    func testLookupWordsAreLowercasedLetterRuns() {
        XCTAssertEqual(KokoroText.lookupWords("In half a mile, turn LEFT. 'Quoted'"),
                       ["in", "half", "a", "mile", "turn", "left", "quoted"])
    }
}
