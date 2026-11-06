import Foundation
import Testing
@testable import MoleBar

struct CSVExportTests {
    @Test func plainFieldsStayUnquoted() {
        #expect(CSVExport.escape("film.mp4") == "film.mp4")
    }

    @Test func commasQuotesAndNewlinesAreQuoted() {
        #expect(CSVExport.escape("a,b") == "\"a,b\"")
        #expect(CSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExport.escape("satır\nikinci") == "\"satır\nikinci\"")
    }

    @Test func formulaPrefixesAreNeutralised() {
        // Elektronik tablo "=" "+" "-" "@" ile başlayan hücreyi formül sayar.
        #expect(CSVExport.escape("=HYPERLINK(\"x\")").hasPrefix("\"'="))
        #expect(CSVExport.escape("+1").hasPrefix("'+"))
        #expect(CSVExport.escape("-2").hasPrefix("'-"))
        #expect(CSVExport.escape("@SUM(A1)").hasPrefix("'@"))
    }

    @Test func buildsHeaderAndRows() {
        let text = CSVExport.make(header: ["Ad", "Boyut"], rows: [["a.zip", "100"], ["b,c", "7"]])
        #expect(text == "Ad,Boyut\na.zip,100\n\"b,c\",7\n")
    }

    @Test func emptyRowsGiveOnlyTheHeader() {
        #expect(CSVExport.make(header: ["Ad"], rows: []) == "Ad\n")
    }
}
