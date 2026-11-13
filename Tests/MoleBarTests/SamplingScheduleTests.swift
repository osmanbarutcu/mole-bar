import Testing
@testable import MoleBar

@Suite("SamplingSchedule")
struct SamplingScheduleTests {
    @Test("sağlık denetimi ilk turda istenir")
    func healthIsDueOnFirstTick() {
        #expect(SamplingSchedule.isHealthDue(tick: 1))
    }

    @Test("sağlık denetimi 120 saniyede bir istenir, aradaki turlarda istenmez")
    func healthIsDueEveryHealthInterval() {
        let interval = SamplingSchedule.healthEveryTicks
        #expect(SamplingSchedule.isHealthDue(tick: 1 + interval))
        #expect(!SamplingSchedule.isHealthDue(tick: 2))
        #expect(!SamplingSchedule.isHealthDue(tick: 1 + interval / 2))
    }
}
