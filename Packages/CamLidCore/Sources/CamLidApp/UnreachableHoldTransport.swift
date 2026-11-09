import CamLidCore

/// The hold transport of a QA copy. It reaches nothing, because the installed power helper is shared by every CamLid app,
/// and a QA run must never change the owner's sleep state through it.
struct UnreachableHoldTransport: PowerHoldTransport {
    func send(_ action: HoldAction) async -> HoldReply? { nil }
    func close() {}
}
