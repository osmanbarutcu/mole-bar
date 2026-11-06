import Foundation
import Testing
@testable import MoleBar

@Suite("NetPerProcess.parse")
struct NetPerProcessTests {
    @Test("son blok okunur, süreç kimliği ayrıştırılır")
    func lastBlock() {
        let output = """
        ,bytes_in,bytes_out,
        kernel_task.0,1000,2000,
        Brave Browser H.1202,28820288,328556,
        ,bytes_in,bytes_out,
        Brave Browser H.1202,100,50,
        Mail.22803,410,0,
        """
        let result = NetPerProcess.parse(output)
        #expect(result[1202] == 150)
        #expect(result[22803] == 410)
        #expect(result[0] == nil)
    }

    @Test("aynı kimlik iki satırda toplanır")
    func sumsDuplicates() {
        let output = ",bytes_in,bytes_out,\nnode.7,10,5,\nnode.7,1,1,\n"
        #expect(NetPerProcess.parse(output)[7] == 17)
    }

    @Test("başlıksız veya bozuk çıktı boş döner")
    func malformed() {
        #expect(NetPerProcess.parse("").isEmpty)
        #expect(NetPerProcess.parse("rastgele metin").isEmpty)
    }
}
